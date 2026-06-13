# TASKS-DESIGN.md
## Miko Task Store — Full Specification
### Version: 1.0 | Date: 2026-06-13 | Status: DESIGN

---

## 1. OVERVIEW

Miko owns its task store completely. No external dependencies (dstask eliminated).
Store is a git repo at ~/.tasks/ — flat JSON files, one per task, synced via git.

---

## 2. STORE STRUCTURE

\`\`\`
~/.tasks/
  <repo>/
    <id>.json       # open, in-progress, blocked tasks
    done/
      <id>.json     # completed, cancelled tasks
  .git/
  README.md
\`\`\`

Rules:
- ~/.tasks/ IS the git repo — no subdirectory wrapper
- repo field is always explicit in JSON (never derived from path alone)
- One file per task — atomic writes, no shared state files
- done/ subdirectory per repo — keeps active tasks fast to scan
- git remote: git@github.com:catwilo/miko-tasks.git

---

## 3. TASK HIERARCHY

3 levels maximum. No infinite nesting.

  task        — primary unit of work (top level, no parent)
  subtask     — concrete step within a task (parent = task ID)
  step        — atomic action within a subtask (parent = subtask ID)

Rules:
- depth enforced at write time: step cannot have children
- parent field contains scoped ID of parent: e.g. "miko-task#5"
- display order: priority DESC, then created_at ASC within same priority
- hierarchy displayed as tree in miko next output

---

## 4. SCOPED IDs

Format: <repo>#<n>

Examples: miko-task#1, noemap#5, clipso#12

Rules:
- n is a per-repo monotonic integer starting at 1
- ID file: ~/.tasks/<repo>/.next_id (integer, incremented atomically)
- lockfile: ~/.tasks/<repo>/.lock — held during ID generation + file write
- IDs never reused — done tasks keep their ID in done/ directory
- Legacy dstask IDs (1-90 global) documented in ~/.tasks/MIGRATION-LOG.md

---

## 5. JSON SCHEMA

### Required fields (always present)
\`\`\`json
{
  "id":         "miko-task#12",
  "repo":       "miko-task",
  "title":      "Implement store lib",
  "status":     "open",
  "priority":   "P1",
  "depth":      "task",
  "created_at": "2026-06-13T10:00:00Z",
  "updated_at": "2026-06-13T10:00:00Z"
}
\`\`\`

### Optional fields
\`\`\`json
{
  "parent":       "miko-task#5",
  "due":          "2026-06-20T00:00:00Z",
  "started_at":   "2026-06-13T11:00:00Z",
  "completed_at": "2026-06-14T09:00:00Z",
  "blocks":       ["noemap#3", "clipso#7"],
  "blocked_by":   ["miko-task#8"],
  "tags":         ["infra", "breaking-change"],
  "notes": [
    {"ts": "2026-06-13T12:00:00Z", "text": "Decided to use Python for YAML parsing"}
  ]
}
\`\`\`

### Field definitions
| Field        | Type            | Required | Notes                                      |
|--------------|-----------------|----------|--------------------------------------------|
| id           | string          | yes      | format: <repo>#<n>                         |
| repo         | string          | yes      | always explicit, never derived from path   |
| title        | string          | yes      | human-readable task description            |
| status       | enum            | yes      | open/in-progress/blocked/done/cancelled    |
| priority     | enum            | yes      | P1/P2/P3/P4 — P1 highest                  |
| depth        | enum            | yes      | task/subtask/step                          |
| created_at   | ISO8601 UTC     | yes      | set at creation, never modified            |
| updated_at   | ISO8601 UTC     | yes      | updated on every write                     |
| parent       | string          | no       | scoped ID of parent task/subtask           |
| due          | ISO8601 UTC     | no       | deadline                                   |
| started_at   | ISO8601 UTC     | no       | set automatically when status→in-progress  |
| completed_at | ISO8601 UTC     | no       | set automatically when status→done/cancelled |
| blocks       | array[string]   | no       | scoped IDs this task blocks                |
| blocked_by   | array[string]   | no       | NEVER set manually — written by store atomically when another task sets blocks |
| tags         | array[string]   | no       | free-form labels for cross-repo filtering  |
| notes        | array[object]   | no       | {ts: ISO8601, text: string} — append only  |

---

## 6. BLOCKING MODEL

Rules:
- Only `blocks` is set by the user/LLM
- `blocked_by` is ALWAYS written by store atomically — never manually
- When task A sets blocks: [B, C]:
    store writes blocks:[B,C] to A
    store appends A to blocked_by[] in B and C
    all 3 writes happen in single operation under lockfile
- When task A is done/cancelled:
    store removes A from blocked_by[] of all tasks A was blocking
    atomic operation under lockfile
- blocked_by is computed/maintained by store — never trusted from disk alone
  (store always verifies consistency on read)

---

## 7. GIT FLOW

Model: trunk-based development (Google/Stripe standard)

### Branch naming
\`\`\`
main          — always deployable, always green, protected
feat/<name>   — new feature, max lifetime 2 days
fix/<name>    — bugfix, max lifetime 1 day
chore/<name>  — maintenance, no logic changes
\`\`\`

### Commit convention (mandatory)
\`\`\`
feat(scope): description
fix(scope): description
chore(scope): description
docs(scope): description
refactor(scope): description
\`\`\`
- scope = affected component
- subject <= 60 chars, imperative, English, no period
- example: fix(store): handle lockfile timeout on slow Android FS

### PR flow
1. git pull --rebase origin main
2. git checkout -b feat/<name>
3. atomic commits
4. git push origin feat/<name>
5. open PR on GitHub
6. CI runs automatically (shellcheck + bash -n)
7. human reviews + approves
8. squash merge to main
9. branch deleted immediately

### LKG tags (replaces LKG in micro ctx)
\`\`\`
git tag -a lkg/<repo> -m "description"
git push origin lkg/<repo>
git checkout lkg/<repo>        # rollback
git diff lkg/<repo> main       # what changed since last good
\`\`\`

### Rules
- LLM never commits, never merges, never pushes — emits commands only
- Human verification required before any commit: exact word "verifico"
- No direct commits to main — branch always, even for 1-line fixes
- Squash merge keeps main linear — bisect works perfectly

---

## 8. MICRO CTX REDUCED SCHEMA

New schema — 3 sections only:

\`\`\`markdown
# <repo> — context

## stack
- lang, entry point, libs, build command, key paths

## rules
- do-NOT constraints specific to this repo
- binding equal to ai.md rules

## architecture
- active design decisions
- NOT historical — history lives in git log + git notes
\`\`\`

Removed from micro ctx:
- pending blocks → task store (~/.tasks/)
- last-known-good → git tag lkg/<repo>
- fix history → git log + git notes

---

## 9. CI PIPELINE

Tool: GitHub Actions
Trigger: every PR to main
Checks (mandatory, blocks merge if failing):
1. shellcheck on all .sh files
2. bash -n syntax check on all .sh files
3. python3 -m py_compile on all .py files

Pilot: miko-task first, then roll out to all repos tagged tool/cli/svc

---

## 10. MIGRATION FROM DSTASK

Script: ~/.tasks/migrate-dstask.py

Logic:
1. Read all ~/.dstask/*.yml
2. For each task: extract repo: tag → determine target repo
3. Tasks without repo: tag → interactive prompt (never silent default)
4. Write to ~/.tasks/<repo>/<new_scoped_id>.json
5. Log old_id → new_id mapping to ~/.tasks/MIGRATION-LOG.md
6. Legacy IDs 1-90 preserved in log — never reused in new store

Post-migration:
- dstask binary decommissioned: removed from ~/.local/bin/ on all nodes
- ~/.dstask/ kept as archive for 30 days, then maid trash

---

## 11. MIKO COMMANDS (post-store)

\`\`\`
miko add -r <repo> "title"           add task (repo always required)
miko add -r <repo> -p <id> "title"   add subtask/step (parent required)
miko add-batch -r <repo>             read tasks from stdin, one per line
miko done <id>                       mark done (current)
miko done -r <repo> <n>              mark done by scoped ID (post-store)
miko block <id-a> <id-b>             A blocks B (store handles blocked_by)
miko next [-r <repo>]                show tasks, priority order, tree view
miko sync [-m msg]                   git -C ~/.tasks pull+push
\`\`\`

---

## 12. SESSION START (post-store)

Complete picture requires BOTH:
1. miko ai <repo>     — reads micro ctx (stack/rules/architecture)
2. miko next -r <repo> — reads active tasks from store

Neither alone is sufficient. ai.md R6.6 must be updated post-store-impl.

---

## 13. DEVICE + TAILSCALE

noemap devices.db schema (updated):
\`\`\`
alias | user | ip (LAN) | tailscale_ip | type | port
\`\`\`

Auto-select logic in nssh/nrsync/nclip:
- if tailscale active AND peer reachable via tailscale_ip → use tailscale_ip
- else → use ip (LAN)
- transparent to caller — no flags needed

---
*This document is the source of truth for miko store implementation.*
*All IMPL tasks in miko-task reference this spec.*
