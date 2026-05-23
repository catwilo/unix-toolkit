package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

// ── Types ─────────────────────────────────────────────────────────────────────

type SessionStatus string

const (
	StatusActive    SessionStatus = "active"
	StatusPaused    SessionStatus = "paused"
	StatusMigrating SessionStatus = "migrating"
	StatusClosed    SessionStatus = "closed"
)

type Session struct {
	ID         string        `json:"id"`
	AccountID  string        `json:"account_id"`
	AI         string        `json:"ai"`
	Scope      string        `json:"scope"`
	Status     SessionStatus `json:"status"`
	MsgCount   int           `json:"msg_count"`
	TokensUsed int           `json:"tokens_used"`
	StartedAt  time.Time     `json:"started_at"`
	WorkerSock string        `json:"worker_sock"`
}

type CLICommand struct {
	Cmd       string            `json:"cmd"`
	SessionID string            `json:"session_id,omitempty"`
	Payload   string            `json:"payload,omitempty"`
	Options   map[string]string `json:"options,omitempty"`
}

type CLIResponse struct {
	OK    bool        `json:"ok"`
	Data  interface{} `json:"data,omitempty"`
	Error string      `json:"error,omitempty"`
	Event string      `json:"event,omitempty"` // stream | limit | ready | error
}

// ── Orchestrator ──────────────────────────────────────────────────────────────

type Orchestrator struct {
	mu           sync.RWMutex
	sessions     map[string]*Session
	sentinelSock string
	memorySock   string
	dataDir      string
}

func New() *Orchestrator {
	return &Orchestrator{
		sessions:     make(map[string]*Session),
		sentinelSock: envOrDefault("SENTINEL_SOCK", "/tmp/aicli/sentinel.sock"),
		memorySock:   envOrDefault("MEMORY_SOCK", "/tmp/aicli/memory.sock"),
		dataDir:      envOrDefault("DATA_DIR", "/data"),
	}
}

// ── Token monitor ─────────────────────────────────────────────────────────────

var limitPatterns = []string{
	"you've reached", "rate limit", "too many requests",
	"message limit", "quota exceeded", "try again later",
}

func (o *Orchestrator) checkLimit(sess *Session, response string) bool {
	lower := response
	for _, p := range limitPatterns {
		if contains(lower, p) {
			log.Printf("token-monitor: limit detected for %s/%s — pattern '%s'", sess.AccountID, sess.AI, p)
			return true
		}
	}
	// Configurable message-count thresholds (simplified — real impl reads config)
	limits := map[string]int{"claude": 5, "chatgpt": 10, "gemini": 20}
	if thresh, ok := limits[sess.AI]; ok && sess.MsgCount >= thresh {
		log.Printf("token-monitor: message count limit reached for %s/%s (%d/%d)",
			sess.AccountID, sess.AI, sess.MsgCount, thresh)
		return true
	}
	return false
}

// ── Session lifecycle ─────────────────────────────────────────────────────────

func (o *Orchestrator) spawnBrowserWorker(sess *Session) error {
	// Ask sentinel for current allocation
	alloc, err := o.sentinelAllocate()
	if err != nil {
		return fmt.Errorf("sentinel allocate: %w", err)
	}

	workerSock := fmt.Sprintf("/tmp/aicli/worker-%s.sock", sess.ID)
	profileDir := fmt.Sprintf("%s/profiles/%s/%s", o.dataDir, sess.AccountID, sess.AI)
	os.MkdirAll(profileDir, 0700)

	args := []string{
		"run", "--detach", "--rm",
		"--name", fmt.Sprintf("aicli-browser-%s-%s", sess.AccountID, sess.AI),
		"--network", "aicli_internal",
		"--memory", alloc["browser_ram"],
		"--cpus", alloc["browser_cpu"],
		"--memory-swap", alloc["browser_ram"],
		"--shm-size", "512m",
		"--volume", profileDir + ":/profile:rw",
		"--volume", "/tmp/aicli:/tmp/aicli:rw",
		"--env", "AI=" + sess.AI,
		"--env", "ACCOUNT_ID=" + sess.AccountID,
		"--env", "PROFILE_DIR=/profile",
		"--env", "WORKER_SOCK=" + workerSock,
		"--env", "CHROME_FLAGS=--no-sandbox --disable-dev-shm-usage --disable-gpu",
		"aicli-browser-worker:latest",
	}

	cmd := exec.Command("podman", args...)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("podman run: %v — %s", err, out)
	}

	sess.WorkerSock = workerSock
	sess.Status = StatusActive
	log.Printf("spawned browser-worker for %s/%s (RAM:%s CPU:%s)",
		sess.AccountID, sess.AI, alloc["browser_ram"], alloc["browser_cpu"])
	return nil
}

func (o *Orchestrator) sentinelAllocate() (map[string]string, error) {
	conn, err := net.Dial("unix", o.sentinelSock)
	if err != nil {
		// Fallback defaults when sentinel is not reachable
		return map[string]string{"browser_ram": "1200m", "browser_cpu": "1.5"}, nil
	}
	defer conn.Close()
	json.NewEncoder(conn).Encode(map[string]string{"cmd": "allocate", "component": "browser-worker"})
	var resp map[string]interface{}
	json.NewDecoder(conn).Decode(&resp)
	alloc, _ := resp["allocation"].(map[string]interface{})
	result := map[string]string{
		"browser_ram": fmt.Sprintf("%v", alloc["browser_ram"]),
		"browser_cpu": fmt.Sprintf("%v", alloc["browser_cpu"]),
	}
	return result, nil
}

// ── Command router ────────────────────────────────────────────────────────────

func (o *Orchestrator) route(cmd CLICommand) CLIResponse {
	switch cmd.Cmd {
	case "send":
		return o.handleSend(cmd)
	case "session_new":
		return o.handleSessionNew(cmd)
	case "session_list":
		return o.handleSessionList()
	case "session_close":
		return o.handleSessionClose(cmd)
	case "migrate":
		return o.handleMigrate(cmd)
	case "status":
		return o.handleStatus()
	default:
		return CLIResponse{Error: "unknown command: " + cmd.Cmd}
	}
}

func (o *Orchestrator) handleSend(cmd CLICommand) CLIResponse {
	o.mu.RLock()
	sess := o.sessions[cmd.SessionID]
	o.mu.RUnlock()

	if sess == nil {
		return CLIResponse{Error: "session not found"}
	}

	// Forward to browser-worker via its Unix socket
	conn, err := net.DialTimeout("unix", sess.WorkerSock, 5*time.Second)
	if err != nil {
		return CLIResponse{Error: "worker unreachable: " + err.Error()}
	}
	defer conn.Close()

	json.NewEncoder(conn).Encode(map[string]string{
		"cmd":        "send",
		"payload":    cmd.Payload,
		"session_id": sess.ID,
	})

	var workerResp map[string]interface{}
	conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	if err := json.NewDecoder(conn).Decode(&workerResp); err != nil {
		return CLIResponse{Error: "worker timeout or decode error: " + err.Error()}
	}

	text, _ := workerResp["text"].(string)
	tokEst, _ := workerResp["tokenEst"].(float64)

	o.mu.Lock()
	sess.MsgCount++
	sess.TokensUsed += int(tokEst)
	o.mu.Unlock()

	limitHit := o.checkLimit(sess, text)

	return CLIResponse{
		OK:    true,
		Data:  map[string]interface{}{"text": text, "tokens_est": int(tokEst), "limit_hit": limitHit},
		Event: "response",
	}
}

func (o *Orchestrator) handleSessionNew(cmd CLICommand) CLIResponse {
	sess := &Session{
		ID:        generateID(),
		AccountID: cmd.Options["account_id"],
		AI:        cmd.Options["ai"],
		Scope:     cmd.Options["scope"],
		Status:    StatusPaused,
		StartedAt: time.Now(),
	}

	if err := o.spawnBrowserWorker(sess); err != nil {
		return CLIResponse{Error: err.Error()}
	}

	o.mu.Lock()
	o.sessions[sess.ID] = sess
	o.mu.Unlock()

	return CLIResponse{OK: true, Data: sess}
}

func (o *Orchestrator) handleSessionList() CLIResponse {
	o.mu.RLock()
	defer o.mu.RUnlock()
	list := make([]*Session, 0, len(o.sessions))
	for _, s := range o.sessions {
		list = append(list, s)
	}
	return CLIResponse{OK: true, Data: list}
}

func (o *Orchestrator) handleSessionClose(cmd CLICommand) CLIResponse {
	o.mu.Lock()
	sess, ok := o.sessions[cmd.SessionID]
	if ok {
		sess.Status = StatusClosed
		delete(o.sessions, cmd.SessionID)
	}
	o.mu.Unlock()

	// Signal sentinel to release allocation
	if conn, err := net.Dial("unix", o.sentinelSock); err == nil {
		json.NewEncoder(conn).Encode(map[string]string{"cmd": "release", "component": "browser-worker"})
		conn.Close()
	}

	return CLIResponse{OK: true}
}

func (o *Orchestrator) handleMigrate(cmd CLICommand) CLIResponse {
	// Get transfer bundle from memory-engine then open new session
	conn, err := net.Dial("unix", o.memorySock)
	if err != nil {
		return CLIResponse{Error: "memory-engine unreachable: " + err.Error()}
	}
	defer conn.Close()

	json.NewEncoder(conn).Encode(map[string]interface{}{
		"cmd":        "BuildTransferBundle",
		"session_id": cmd.SessionID,
		"scope":      cmd.Options["scope"],
	})

	var bundle map[string]interface{}
	json.NewDecoder(conn).Decode(&bundle)

	return CLIResponse{OK: true, Data: map[string]interface{}{
		"bundle":     bundle,
		"to_account": cmd.Options["to_account"],
		"to_ai":      cmd.Options["to_ai"],
	}}
}

func (o *Orchestrator) handleStatus() CLIResponse {
	o.mu.RLock()
	defer o.mu.RUnlock()
	return CLIResponse{OK: true, Data: map[string]interface{}{
		"active_sessions": len(o.sessions),
		"sessions":        o.sessions,
	}}
}

// ── Main ──────────────────────────────────────────────────────────────────────

func main() {
	sockPath := envOrDefault("ORCHESTRATOR_SOCK", "/tmp/aicli/orchestrator.sock")
	os.MkdirAll("/tmp/aicli", 0700)
	os.Remove(sockPath)

	ln, err := net.Listen("unix", sockPath)
	if err != nil {
		log.Fatalf("orchestrator: cannot bind socket: %v", err)
	}
	os.Chmod(sockPath, 0600)
	log.Printf("orchestrator: listening on %s", sockPath)

	orch := New()

	// Graceful shutdown
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP)
	go func() {
		s := <-sig
		log.Printf("orchestrator: received %s, shutting down", s)
		ln.Close()
		os.Exit(0)
	}()

	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("orchestrator: accept error: %v", err)
			continue
		}
		go func(c net.Conn) {
			defer c.Close()
			scanner := bufio.NewScanner(c)
			enc := json.NewEncoder(c)
			for scanner.Scan() {
				var cmd CLICommand
				if err := json.Unmarshal(scanner.Bytes(), &cmd); err != nil {
					enc.Encode(CLIResponse{Error: "invalid JSON: " + err.Error()})
					continue
				}
				resp := orch.route(cmd)
				enc.Encode(resp)
			}
		}(conn)
	}
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub ||
		func() bool {
			for i := 0; i <= len(s)-len(sub); i++ {
				if s[i:i+len(sub)] == sub {
					return true
				}
			}
			return false
		}())
}

func generateID() string {
	return fmt.Sprintf("%d", time.Now().UnixNano())
}
