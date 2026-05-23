# aicli

> Multi-account AI browser runtime — Claude, ChatGPT, Gemini from terminal.
> Local memory, automatic context migration, byobu TUI.

## Architecture

```
HOST
  aicli (Go static binary)  ──Unix socket──►  PODMAN POD: aicli-pod
  ~/.local/share/aicli/                          ├── resource-sentinel  (Go)
  ~/.config/aicli/                               ├── orchestrator       (Go)
  /tmp/aicli/ (IPC sockets)                      ├── memory-engine      (Rust/SQLite)
                                                 ├── context-compressor (Go)
                                                 └── browser-worker-*   (Node.js/Playwright) ← spawned dynamically
```

**Language decisions:**
- **Go** — sentinel, orchestrator, compressor, CLI: static binaries, fast IPC, goroutines, `/proc` access
- **Rust** — memory-engine: `rusqlite` (fastest SQLite interface), zero-GC latency for transfer bundles
- **Node.js/TS** — browser-worker only: Playwright has no other viable option
- **Shell** — glue scripts and byobu bridge

## Quickstart

```bash
# 1. Clone and setup
git clone <repo> aicli
cd aicli
./scripts/setup.sh

# 2. Edit config
$EDITOR ~/.config/aicli/config.yaml

# 3. Start the pod
systemctl --user enable --now aicli-pod

# 4. Login (opens headed browser)
aicli session new --account personal-1 --ai claude

# 5. Send
aicli send "hello, let's build something"

# Pipe mode
cat src/main.go | aicli send "refactor this"
```

## Key commands

```bash
aicli send "message"                        # send to active session
aicli send --ai chatgpt "message"           # explicit AI
aicli send --file ./main.ts "explain"       # with file context
aicli migrate --to personal-2 --ai gemini  # migrate context on limit
aicli memory pin "always use podman"        # pin a rule permanently
aicli memory list --type pinned             # list pinned memory
aicli status                                # system status
```

## Directory structure

```
containers/
  sentinel/        Go  — reads /proc, adjusts cgroups dynamically
  orchestrator/    Go  — IPC router, session lifecycle, token monitor
  memory-engine/   Rust — SQLite WAL, snapshots, transfer bundles
  compressor/      Go  — heuristic context compression
  browser-worker/  Node.js/TS — Playwright + Chrome adapters
cli/               Go  — static binary for host, talks to orchestrator
podman/            compose.yaml + systemd quadlets
scripts/           setup.sh, build-all.sh, byobu-status.sh
config/            config.example.yaml, prompt templates
```

## Resource model

The `resource-sentinel` reads `/proc/meminfo` and `/proc/stat` directly (no fork/exec).
It allocates 70% of `MemAvailable` to the pod, distributed by priority:
browser workers > memory-engine > orchestrator > compressor.

Browser workers are spawned dynamically with limits computed **at spawn time** from
what the sentinel reports as available at that moment — not from static values in compose.yaml.

## Security notes

- All inter-service traffic is on an internal-only Podman network (no internet access)
- Browser profiles are `chmod 700` — only your user can read them
- Credentials are never stored in YAML — Playwright handles auth via persistent Chrome profiles
- Secrets never appear in environment variables or logs
