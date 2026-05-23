package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
	"sort"
	"strings"
)

// ── Types ─────────────────────────────────────────────────────────────────────

type Message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type CompressRequest struct {
	Messages  []Message `json:"messages"`
	MaxTokens int       `json:"max_tokens"`
	Strategy  string    `json:"strategy"` // heuristic | keywords | structured
}

type CompressResult struct {
	Summary     string   `json:"summary"`
	Done        []string `json:"done"`
	Pending     []string `json:"pending"`
	Constraints []string `json:"constraints"`
	TokensIn    int      `json:"tokens_in"`
	TokensOut   int      `json:"tokens_out"`
	Ratio       float64  `json:"ratio"`
}

// ── Token estimation ──────────────────────────────────────────────────────────

// EstimateTokens: ~4 chars = 1 token (no external model required).
func EstimateTokens(text string) int {
	return (len([]rune(text)) + 3) / 4
}

// ── Heuristic compressor ──────────────────────────────────────────────────────

type scoredMsg struct {
	msg   Message
	score float64
}

// signalPatterns determines importance weight of a message.
func scoreMessage(m Message) float64 {
	content := strings.ToLower(m.Content)
	score := 1.0

	// High-value signals
	if strings.Contains(content, "```") || strings.Contains(content, "func ") ||
		strings.Contains(content, "class ") || strings.Contains(content, "impl ") {
		score *= 3 // code block
	}
	if strings.Contains(content, "http://") || strings.Contains(content, "https://") {
		score *= 2 // URL reference
	}
	for _, kw := range []string{"decision", "constraint", "must", "never", "always",
		"important", "critical", "error", "bug", "fix"} {
		if strings.Contains(content, kw) {
			score *= 2.5
			break
		}
	}

	// Low-value signals
	for _, filler := range []string{"hello", "hi", "thanks", "ok", "sure", "got it",
		"understood", "great", "perfect", "sounds good"} {
		if strings.TrimSpace(content) == filler {
			return 0 // pure filler — eliminate
		}
	}

	// Penalise very short assistant acknowledgements
	if m.Role == "assistant" && EstimateTokens(m.Content) < 15 {
		score *= 0.3
	}

	return score
}

func extractConstraints(messages []Message) []string {
	var out []string
	markers := []string{"decision:", "constraint:", "must:", "never:", "always:", "rule:"}
	for _, m := range messages {
		lower := strings.ToLower(m.Content)
		for _, marker := range markers {
			if idx := strings.Index(lower, marker); idx != -1 {
				line := m.Content[idx:]
				if nl := strings.Index(line, "\n"); nl != -1 {
					line = line[:nl]
				}
				out = append(out, strings.TrimSpace(line))
			}
		}
	}
	return unique(out)
}

func extractPending(messages []Message) []string {
	var out []string
	markers := []string{"todo:", "pending:", "next:", "need to:", "should:"}
	for _, m := range messages {
		if m.Role != "user" {
			continue
		}
		lower := strings.ToLower(m.Content)
		for _, marker := range markers {
			if idx := strings.Index(lower, marker); idx != -1 {
				line := m.Content[idx:]
				if nl := strings.Index(line, "\n"); nl != -1 {
					line = line[:nl]
				}
				out = append(out, strings.TrimSpace(line))
			}
		}
	}
	return unique(out)
}

func compress(req CompressRequest) CompressResult {
	if req.MaxTokens <= 0 {
		req.MaxTokens = 4000
	}

	totalIn := 0
	for _, m := range req.Messages {
		totalIn += EstimateTokens(m.Content)
	}

	// Score all messages
	scored := make([]scoredMsg, 0, len(req.Messages))
	for _, m := range req.Messages {
		s := scoreMessage(m)
		if s > 0 {
			scored = append(scored, scoredMsg{m, s})
		}
	}

	// Sort descending by score
	sort.Slice(scored, func(i, j int) bool {
		return scored[i].score > scored[j].score
	})

	// Build summary within token budget
	var selected []string
	budget := 0
	for _, s := range scored {
		t := EstimateTokens(s.msg.Content)
		if budget+t > req.MaxTokens {
			break
		}
		selected = append(selected, fmt.Sprintf("[%s] %s", s.msg.Role, s.msg.Content))
		budget += t
	}

	summary := strings.Join(selected, "\n\n")

	return CompressResult{
		Summary:     summary,
		Done:        []string{},
		Pending:     extractPending(req.Messages),
		Constraints: extractConstraints(req.Messages),
		TokensIn:    totalIn,
		TokensOut:   EstimateTokens(summary),
		Ratio:       float64(budget) / float64(max(totalIn, 1)),
	}
}

// ── Main ──────────────────────────────────────────────────────────────────────

func main() {
	sockPath := envOrDefault("COMPRESSOR_SOCK", "/tmp/aicli/compressor.sock")
	os.MkdirAll("/tmp/aicli", 0700)
	os.Remove(sockPath)

	ln, err := net.Listen("unix", sockPath)
	if err != nil {
		log.Fatalf("compressor: cannot bind socket: %v", err)
	}
	os.Chmod(sockPath, 0600)
	log.Printf("compressor: listening on %s", sockPath)

	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("compressor: accept error: %v", err)
			continue
		}
		go func(c net.Conn) {
			defer c.Close()
			scanner := bufio.NewScanner(c)
			enc := json.NewEncoder(c)
			for scanner.Scan() {
				var req CompressRequest
				if err := json.Unmarshal(scanner.Bytes(), &req); err != nil {
					enc.Encode(map[string]string{"error": err.Error()})
					continue
				}
				result := compress(req)
				enc.Encode(result)
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

func unique(ss []string) []string {
	seen := make(map[string]bool)
	out := ss[:0]
	for _, s := range ss {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
