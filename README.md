# ut — unix-toolkit repo manager

Manages all repos in the catwilo ecosystem across Termux, Debian, and macOS.
Source of truth: repos.tsv. Works with miko (task + ctx) and gh (GitHub CLI).

---

## Installation

```sh
git clone git@github.com:catwilo/unix-toolkit.git ~/unix-toolkit
export PATH="$HOME/unix-toolkit:$PATH"  # add to ~/.zshenv
```

All repos clone into ~/unix-toolkit-tools/<name>/.

---

## Commands

### ut sync
Fetch all remotes, show cross-repo status. Non-destructive.
```sh
ut sync
```

### ut status
Only repos with something to report. Summary line format:
```sh
ut status
# [32 repos] ✓ 30 clean  ⚡ 2 ahead  ✗ 0 conflict
```

### ut push
Push all repos ahead of remote. Called internally by miko sync.
```sh
ut push
```
In daily workflow use miko sync — runs dstask + ut push in order.

### ut clone
Clone all repos in repos.tsv not yet present locally.
```sh
ut clone           # all missing
ut clone noemap    # one specific repo
```
Always uses SSH (git@github.com:catwilo/<repo>.git).

### ut list
List all repos with tags and description.
```sh
ut list
ut list tool       # filter by tag
```

### ut tag
Show or filter repos by tag.
```sh
ut tag             # all tags in use
ut tag cfg         # repos tagged cfg
```

### ut add
Register a new repo in repos.tsv. Does not create the GitHub repo.
```sh
ut add <repo> <tags> "<description>"
ut add deadd-setup tool,cfg "deadd notification center config + scripts"
```

### ut rm
Remove a repo from repos.tsv. Does not delete the local clone.
```sh
ut rm correccionLatex
```

### ut run
Run a command in every cloned repo.
```sh
ut run git log --oneline -1
```

### ut health
Check each repo: missing remote, HTTPS remote, untracked files, no commits.
```sh
ut health
```

### ut diff
Show uncommitted changes across all repos.
```sh
ut diff
ut diff zsh-setup
```

### ut machines
List registered devices via noemap — OS, repo count, sync state.
```sh
ut machines
# ── d0 [debian] ── ✓ 31 repos synced
# ── tx [android] ── ✓ 31 repos synced
```

---

## repos.tsv

Tab-separated: name / tags / description. Managed by ut add / ut rm.

```
clipso    tool,cli    copy anything to clipboard across environments
noemap    tool,net    LAN discovery and SSH device mapper
zsh-setup cfg         dotfiles + zsh installer for all platforms
```

---

## Tag vocabulary

| Tag    | Meaning                        |
|--------|--------------------------------|
| tool   | CLI tool, daily use            |
| cli    | command-line interface         |
| cfg    | dotfiles / configuration       |
| util   | small utility, no installer    |
| infra  | infrastructure / provisioning  |
| net    | networking                     |
| sec    | security / audit               |
| svc    | background service             |
| core   | foundational dependency        |
| client | client project (external)      |
| web    | web frontend                   |
| arc    | archived / reference only      |
| game   | game or emulation project      |
| fw     | firmware / kernel driver       |
| bot    | automation bot                 |

---

## Integration

- miko owns all .ctx.md files and task state. Use miko sync for full sync.
- gh required for GitHub operations (repo create, etc).
- noemap provides device aliases used by ut machines.

---

→ [Project portfolio](PORTFOLIO.md)
