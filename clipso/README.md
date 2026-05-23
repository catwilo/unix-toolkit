# clipso

Copy local files, remote files, or stdin to the clipboard. Detects the
environment and picks the right backend, with OSC52 as the universal
fallback for SSH and headless sessions.

Targets: Termux (ARM64, non-root), Debian, Arch Linux.
Backends: `termux-clipboard-set`, `wl-copy` (Wayland), `xclip` (X11),
OSC52 escape sequence (SSH/tmux/screen/headless).

## Usage

    clipso <file>                  copy a local file
    clipso user@host:/path/file    copy a remote file over SSH
    clipso -p 2222 user@host:/f    remote with a custom SSH port
    clipso -                       read stdin
    echo hello | clipso            read piped stdin

Payload limit is 10 MB. Empty input is rejected.

## SSH dual-clipboard

When run inside an SSH session, clipso copies to the server's local
clipboard (if a backend is available) and also mirrors to the client
terminal's clipboard via OSC52, so the content lands wherever you are.
Headless servers use OSC52 only (no duplication).

## clipc helper

When installed via noemap, a `clipc` zsh function is available:

    clipc -- some text       copy the rest of the line literally
    clipc                    read stdin until Ctrl-D, then copy

`clipc` (no args) is the stable way to copy a pasted multi-line block:
run it, paste, press Ctrl-D. Single quotes are required for literal
`-- text` containing `;`, `$`, quotes, or backticks, since the shell
expands the line before clipso sees it.

## Environment

- `NO_COLOR` — disable colored log output (also auto-disabled when
  stderr is not a TTY).
- `TMUX` / `STY` — detected automatically for OSC52 passthrough.
