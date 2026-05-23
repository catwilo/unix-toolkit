package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

// ── IPC client ────────────────────────────────────────────────────────────────

const orchestratorSock = "/tmp/aicli/orchestrator.sock"

type cliReq struct {
	Cmd       string            `json:"cmd"`
	SessionID string            `json:"session_id,omitempty"`
	Payload   string            `json:"payload,omitempty"`
	Options   map[string]string `json:"options,omitempty"`
}

type cliResp struct {
	OK    bool            `json:"ok"`
	Data  json.RawMessage `json:"data,omitempty"`
	Error string          `json:"error,omitempty"`
	Event string          `json:"event,omitempty"`
}

func send(req cliReq) (*cliResp, error) {
	conn, err := net.DialTimeout("unix", orchestratorSock, 3*time.Second)
	if err != nil {
		return nil, fmt.Errorf("cannot connect to orchestrator at %s: %w\n"+
			"Is the aicli pod running? Try: systemctl --user start aicli-pod", orchestratorSock, err)
	}
	defer conn.Close()

	line, _ := json.Marshal(req)
	conn.Write(append(line, '\n'))

	var resp cliResp
	if err := json.NewDecoder(conn).Decode(&resp); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}
	return &resp, nil
}

// renderMarkdown pipes text through `glow` if available, else prints raw.
func renderMarkdown(text string) {
	glowPath, err := exec.LookPath("glow")
	if err != nil {
		fmt.Println(text)
		return
	}
	cmd := exec.Command(glowPath, "-")
	cmd.Stdin = strings.NewReader(text)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Println(text)
	}
}

// currentSession returns the session ID stored in /tmp/aicli/current_session,
// or exits with a helpful message if not set.
func currentSession() string {
	data, err := os.ReadFile("/tmp/aicli/current_session")
	if err != nil || strings.TrimSpace(string(data)) == "" {
		fmt.Fprintln(os.Stderr, "No active session. Start one with: aicli session new --account <id> --ai <claude|chatgpt|gemini>")
		os.Exit(1)
	}
	return strings.TrimSpace(string(data))
}

func saveCurrentSession(id string) {
	os.MkdirAll("/tmp/aicli", 0700)
	os.WriteFile("/tmp/aicli/current_session", []byte(id), 0600)
}

// ── Commands ──────────────────────────────────────────────────────────────────

func cmdSend(accountFlag, aiFlag, scopeFlag, fileFlag string, dryRun bool) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "send [message]",
		Short: "Send a message to the active AI session",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			var payload string

			// Build payload from arg, stdin pipe, or file
			if len(args) > 0 {
				payload = args[0]
			}

			stat, _ := os.Stdin.Stat()
			if (stat.Mode() & os.ModeCharDevice) == 0 {
				// Data available on stdin
				buf := new(strings.Builder)
				io.Copy(buf, os.Stdin)
				if payload != "" {
					payload = payload + "\n\n" + buf.String()
				} else {
					payload = buf.String()
				}
			}

			if fileFlag != "" {
				fc, err := os.ReadFile(fileFlag)
				if err != nil {
					return fmt.Errorf("read file: %w", err)
				}
				payload = payload + "\n\n```\n" + string(fc) + "\n```"
			}

			if payload == "" {
				return fmt.Errorf("no message provided")
			}

			if dryRun {
				fmt.Printf("[dry-run] Would send to %s/%s (scope: %s):\n%s\n",
					accountFlag, aiFlag, scopeFlag, payload)
				return nil
			}

			resp, err := send(cliReq{
				Cmd:       "send",
				SessionID: currentSession(),
				Payload:   payload,
				Options:   map[string]string{"account": accountFlag, "ai": aiFlag, "scope": scopeFlag},
			})
			if err != nil {
				return err
			}
			if !resp.OK {
				return fmt.Errorf("orchestrator error: %s", resp.Error)
			}

			var data map[string]interface{}
			json.Unmarshal(resp.Data, &data)

			if text, ok := data["text"].(string); ok {
				renderMarkdown(text)
			}

			if limitHit, _ := data["limit_hit"].(bool); limitHit {
				fmt.Fprintln(os.Stderr, "\n⚠  LÍMITE DETECTADO — ejecuta 'aicli migrate' para continuar")
			}
			return nil
		},
	}
	cmd.Flags().StringVar(&accountFlag, "account", "", "Account ID to use")
	cmd.Flags().StringVar(&aiFlag, "ai", "", "AI to use: claude|chatgpt|gemini")
	cmd.Flags().StringVar(&scopeFlag, "scope", "", "Scope for memory injection")
	cmd.Flags().StringVar(&fileFlag, "file", "", "Path to file to include as context")
	cmd.Flags().BoolVar(&dryRun, "dry-run", false, "Show what would be sent without sending")
	return cmd
}

func cmdSessionNew() *cobra.Command {
	var accountID, ai, scope string
	cmd := &cobra.Command{
		Use:   "new",
		Short: "Start a new browser session",
		RunE: func(cmd *cobra.Command, args []string) error {
			resp, err := send(cliReq{
				Cmd: "session_new",
				Options: map[string]string{
					"account_id": accountID,
					"ai":         ai,
					"scope":      scope,
				},
			})
			if err != nil {
				return err
			}
			if !resp.OK {
				return fmt.Errorf("orchestrator: %s", resp.Error)
			}
			var sess map[string]interface{}
			json.Unmarshal(resp.Data, &sess)
			id := fmt.Sprintf("%v", sess["id"])
			saveCurrentSession(id)
			fmt.Printf("✓ Session started: %s (%s/%s)\n", id, accountID, ai)
			return nil
		},
	}
	cmd.Flags().StringVar(&accountID, "account", "", "Account ID (required)")
	cmd.Flags().StringVar(&ai, "ai", "claude", "AI: claude|chatgpt|gemini")
	cmd.Flags().StringVar(&scope, "scope", "general", "Memory scope")
	cmd.MarkFlagRequired("account")
	return cmd
}

func cmdSession() *cobra.Command {
	c := &cobra.Command{Use: "session", Short: "Manage browser sessions"}
	c.AddCommand(
		cmdSessionNew(),
		&cobra.Command{
			Use:   "list",
			Short: "List active sessions",
			RunE: func(cmd *cobra.Command, args []string) error {
				resp, err := send(cliReq{Cmd: "session_list"})
				if err != nil {
					return err
				}
				fmt.Println(string(resp.Data))
				return nil
			},
		},
	)
	return c
}

func cmdMigrate() *cobra.Command {
	var toAccount, toAI string
	cmd := &cobra.Command{
		Use:   "migrate",
		Short: "Migrate context to another account/AI",
		RunE: func(cmd *cobra.Command, args []string) error {
			resp, err := send(cliReq{
				Cmd:       "migrate",
				SessionID: currentSession(),
				Options: map[string]string{
					"to_account": toAccount,
					"to_ai":      toAI,
					"scope":      "general",
				},
			})
			if err != nil {
				return err
			}
			if !resp.OK {
				return fmt.Errorf("migrate: %s", resp.Error)
			}
			fmt.Printf("✓ Migration bundle ready → %s/%s\n", toAccount, toAI)
			fmt.Println(string(resp.Data))
			return nil
		},
	}
	cmd.Flags().StringVar(&toAccount, "to", "", "Target account ID (required)")
	cmd.Flags().StringVar(&toAI, "ai", "claude", "Target AI")
	cmd.MarkFlagRequired("to")
	return cmd
}

func cmdStatus() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Show system status",
		RunE: func(cmd *cobra.Command, args []string) error {
			conn, err := net.DialTimeout("unix", "/tmp/aicli/sentinel.sock", 2*time.Second)
			if err == nil {
				defer conn.Close()
				json.NewEncoder(conn).Encode(map[string]string{"cmd": "status"})
				var status map[string]interface{}
				json.NewDecoder(conn).Decode(&status)
				fmt.Printf("sentinel: RAM avail %vMB  CPU idle %.1f%%  pressure: %v\n",
					status["ram_available_mb"], status["cpu_idle_pct"], status["memory_pressure"])
			}

			resp, err := send(cliReq{Cmd: "status"})
			if err != nil {
				return err
			}
			fmt.Println(string(resp.Data))
			return nil
		},
	}
}

// ── Byobu bridge ──────────────────────────────────────────────────────────────

func cmdByobuBridge() *cobra.Command {
	return &cobra.Command{
		Use:    "byobu-bridge",
		Hidden: true,
		Short:  "Write orchestrator events to byobu history file",
		RunE: func(cmd *cobra.Command, args []string) error {
			histDir := os.ExpandEnv("$HOME/.local/share/aicli/history")
			os.MkdirAll(histDir, 0700)
			f, err := os.OpenFile(histDir+"/active.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
			if err != nil {
				return err
			}
			defer f.Close()
			w := bufio.NewWriter(f)
			for {
				scanner := bufio.NewScanner(os.Stdin)
				for scanner.Scan() {
					fmt.Fprintln(w, scanner.Text())
					w.Flush()
				}
			}
		},
	}
}

// ── Root ──────────────────────────────────────────────────────────────────────

func main() {
	root := &cobra.Command{
		Use:   "aicli",
		Short: "Multi-account AI browser runtime CLI",
		Long: `aicli — local AI session manager for Claude, ChatGPT and Gemini.
Communicates with the orchestrator via Unix socket at /tmp/aicli/orchestrator.sock`,
	}

	var accountFlag, aiFlag, scopeFlag, fileFlag string
	var dryRun bool

	root.PersistentFlags().StringVar(&accountFlag, "account", "", "Account ID")
	root.PersistentFlags().StringVar(&aiFlag, "ai", "", "AI: claude|chatgpt|gemini")
	root.PersistentFlags().StringVar(&scopeFlag, "scope", "general", "Memory scope")

	root.AddCommand(
		cmdSend(accountFlag, aiFlag, scopeFlag, fileFlag, dryRun),
		cmdSession(),
		cmdMigrate(),
		cmdStatus(),
		cmdByobuBridge(),
	)

	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}
