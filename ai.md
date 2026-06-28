# COMMAND SUGGESTION FORMAT SPEC — Enterprise Standard

Code, variables, comments: English. Conversational reply: Spanish.
Stack: Termux (Android), Debian (db). Tools: mkit, miko, ut, noemap,
nssh, nscp, nclip, ncssh, ndevs, nrsync, maid, clipso.

## QUALITY BASELINE

Every command or code suggestion: reproducible, auditable, minimal
blast radius, state proven by real output, never by assertion. Default
behavior, not something to request per turn.

## COMMAND BLOCK FORMAT

Target-machine header (pictograph + label) immediately followed by the
command block, no text between them:

  # 💻 COMPUTADOR (Debian/db)
  # 📱 CELULAR (Termux/Android)

Header indicates where; block indicates what. Risk warnings or relevant
notes go before or after the block, never between header and command.

## ENUMERABLE-OPTION DECISIONS

Present as short tappable options instead of prose only when the answer
cannot be resolved by reading an existing file or running `--help`. If
resolvable that way, resolve first.

## OWN TOOLS AS SOURCE OF TRUTH

First suggested use of any custom tool (mkit, miko, ut, noemap, nssh,
nscp, nclip, ncssh, ndevs, nrsync, maid, clipso) per conversation:
suggest `--help` before suggesting its use. Tool behavior may have
changed since any prior knowledge; `--help` output is current, memory
isn't. Exempt: standard POSIX commands (ls, cd, grep).

## CLIPSO — USAGE

Two forms only:

**`clipso run cmd1; cmd2`** — executes one or more commands, captures
  combined stdout+stderr into one copyable unit.

**`clipso read <file>`** — reads file content into one copyable unit.

No other invocation form is used. No piping into clipso.

## EXECUTION CONVENTIONS

**Any output-producing command:** `clipso run cmd1; cmd2`

**State change + verification:** same block. Unverified state between
  turns is the failure mode this avoids.

**Silent failure (no output):** re-run capturing stderr explicitly via
  `clipso run cmd1; cmd2` before any other step.

**Same error 3 times:** stop, propose a different approach instead of
  repeating minor variations.

**Background process:** always paired with its kill command in the
  same block.

**Secrets (tokens, keys, sensitive IPs):** masked before appearing in
  any suggested output.

## FILESYSTEM

Confirm a file exists before suggesting any operation on it.

**Read:** `clipso read <file>`, full file always. Multiple files: one
  `clipso read` call per file.

**Before planning a change to a tool:** read its full source, not just
  the apparently relevant part.

**Write/edit:** `mkit` (write for full files, patch-line for single
  lines, patch-inline for multi-line, anchor for assertions). Built-in
  .new -> verify -> mv pattern, atomic, preserves permissions — standard
  method.
  If mkit unusable: write `.new` -> verify -> restore permissions -> mv.
  Never overwrite in place.

**Delete:** `maid trash <file>` (recoverable) by default. `rm` and
  overwrite-over-existing only on explicit in-the-moment request.

## BATCH EDITING

All edits to the same file: one branch, each verified individually, one
`ut ship` + `ut deploy` + `miko sync` cycle at the end. Cycle cost is
fixed (~85s); N edits cost 1 cycle, not N.

`patch-inline` default for multi-line edits (no temp files, no anchor
needed). `patch-line` for single lines. `mkit patch <dest> <patch.py>`
last resort only.

Post-edit tests run against source binary at
`~/unix-toolkit-tools/<repo>/<bin>`: `ut deploy` first, then test the
installed binary.

## TASKS

`miko add / edit / done` for individual management. Each task: type
(BUG/FEAT/CHORE/DESIGN), exact reproducible symptom, root cause if
known, expected behavior.

Destructive task operations: create new state first, verify it exists,
only then destroy the old. `miko move` handles this atomically.

Tasks manageable from any node; `miko sync` reconciles across all.

## DEPLOYMENT

`ut ship -> ut deploy -> miko sync`, strict order. ship merges+pushes;
deploy installs across all nodes; sync reconciles tasks only after new
state is live. Syncing before tasks are marked done propagates stale
task state to all nodes.

A fix to a shared tool is incomplete until `ut deploy <tool>` has run on
every node using it. Source of truth: the repo
(`~/unix-toolkit-tools/<tool>`), never `~/.local/bin` directly.

## GIT — STANDARD FLOW

Global pre-commit hook blocks direct commits on main/master per repo.
Pre-template repos: `git init` repopulates hooks non-destructively.
`git commit --no-verify`: intentional bypass, rare.

Per-fix flow:
1. `git pull --rebase origin main`
2. `git checkout -b <type>/<name>` (feat | fix | chore | refactor | docs)
3. Make the fix on that branch
4. Confirmation before commit
5. Commit: `type(scope): description`, <=60 chars, imperative, English
6. `ut ship <repo>` — merge, push, delete branch
7. `ut deploy <repo>` — install locally, distribute to all nodes
8. `miko micro <repo>` — full task list
9. `miko done <id>` per task resolved by this deploy
10. Confirm whether to continue with another change or open another
    repo before syncing
11. `miko sync` last, on confirmation

Order rationale: sync must reflect deployed state and resolved tasks.
Syncing before step 9 propagates stale task state.

**Before any push:** `git diff --stat origin/main`.

**`git push --force`/`--force-with-lease`:** explicit request only.

**Before `git revert`:** show `git log --oneline -3`, name exact commit.

**Before `git checkout <file>`:** capture changes first (`git stash` or
  `git diff HEAD <file>`).

**Regression, no clear last-known-good:** `git bisect` anchored to `lkg`
  tag.

**Confirmed stable state:** annotated tag:
  `git tag -a lkg -m "lkg: <desc>" -f && git push origin lkg -f`

## REMOTE

Connect: `nssh <alias>` — alias carries correct host/user/options.

Multi-step or state-changing work: interactive shell session. Exec mode
(`nssh alias "cmd"`): quick single-command reads only.

**Remote access config changes (SSH, firewall):** confirm alternate
access path exists, add new access, verify it works, only then remove
old. A wrong change to the only access path locks out with no recovery.

**Service restarts (sshd, etc.):** only when config change requires it;
verify reachability with a real connection afterward. Running process
≠ accepting service.

Device management: `noemap / nssh / nscp`.

## DEBUG

Real state from current conversation only — never carry state from a
previous session.

Full repo read before diagnosing = structure (find/ls) + relevant file
content (`clipso read`) + `git status --short` + `git log --oneline
origin/main..HEAD`.

Before switching machines mid-session: verify current machine has no
unpushed commits, no unmerged branches.

## ENCODING

Plain ASCII default in all generated content (code, comments, files,
here-docs). Non-ASCII bytes have been silently mangled in here-docs in
this environment. Required non-ASCII (Spanish prose, proper names):
`python3` or `mkit write` — never a raw here-doc.

## DOTFILES

`zsh-setup/dotfiles/` = canonical source, all platforms. `install.sh`
idempotent, `cp -RfL` (copy, never symlink). `~/.addons-zsh/aliass/`
copied from `zsh-setup/dotfiles/.addons-zsh/aliass/`.

`install.sh` appending to an rc file that's a symlink to a versioned
dotfile: skip append, warn only.

## SESSION

**Open:** `clipso run miko next --all` — all pending tasks before
  choosing a work target.

**Repo open:** one block per state check:
  `clipso run miko micro <repo>`
  `clipso run git -C <repopath> fetch origin`
  `clipso run git -C <repopath> diff --stat origin/main..HEAD`
  `clipso run git -C <repopath> diff --stat HEAD..origin/main`
  `clipso run git -C <repopath> branch -v --no-merged main`
  `clipso run git -C <repopath> status --short`

  `miko -h` once per conversation, own block, before repo-open block.

**Close:** `clipso run miko session-close` — pending tasks, sync, dirty
  repos. Session close confirmed only by this output.

## RISK

High-impact commands (firewall, disk, `git push --force`, package
install): one-line warning, explicit confirmation required before
suggesting execution.
