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
# [32 repos] ✓ 28 clean  ⚡ 2 ahead  ⏮ 1 behind  ✗ 1 conflict
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

### ut machines diff
Compare git state of every repo across all nodes (local + remote) to spot divergence.
Runs a POSIX collector on each node via `nssh --raw` and prints one row per repo.

    ut machines diff
    # repo  local <hash>  db <hash>  tx <hash>[branch:][↑ahead][*dirty]

Cell format: `[branch:]hash[↑N][*M]` — branch shown only when not main, `↑N` commits ahead, `*M` dirty files. Differing hashes across columns = divergence. Unreachable nodes marked `unreach`.

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

### ut create
Register and create a new GitHub repo, add to repos.tsv, clone locally.
```sh
ut create <repo> <tags> "<description>"
```

### ut delete
Delete GitHub repo, remove from repos.tsv, move local clone to trash.
```sh
ut delete <repo>
```

### ut rename
Rename GitHub repo, update repos.tsv, move local clone directory.
```sh
ut rename <old> <new>
```

### ut open
Open repo on GitHub in the browser.
```sh
ut open <repo>
```

### ut info
Show repo metadata, remote URL, branch, ahead/dirty status, recent commits.
```sh
ut info <repo>
```

### ut ship
After verifico: rebase branch onto origin/main, merge, push, delete branch.
```sh
ut ship <repo>
```
Human executes after confirming fix works. Never call autonomously.

### ut distribute
Pull and reinstall a repo on every reachable node via noemap.
```sh
ut distribute <repo>
```
Skips nodes where repo is not cloned. Reports unreachable nodes.

---

→ [Project portfolio](PORTFOLIO.md)
