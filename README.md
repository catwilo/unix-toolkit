# catwilo/unix-toolkit — portfolio index

A collection of command-line tools built to solve real problems on Linux, Termux (Android), and macOS. Each one started from a concrete need, runs in production on my own machines, and is written to be portable, safe to re-run, and clear to maintain.

---

## Repos

### [noemap](https://github.com/catwilo/noemap)
LAN discovery and SSH device mapper. Scans the network, identifies reachable machines, detects OS, and lets you reach any device by a short alias. Works identically on Debian and non-root Termux.

### [clipso](https://github.com/catwilo/clipso)
Copy anything to your clipboard, anywhere. Detects the environment (Termux, Wayland, X11, SSH) and picks the right backend automatically — falling back to OSC52 so content lands on the machine you're actually sitting at.

### [aicli](https://github.com/catwilo/aicli)
Multi-account AI runtime from the terminal. Containerized setup for driving Claude, ChatGPT, and Gemini from one interface, with separate browser workers per account and a Podman-based orchestration layer.

### [streaming](https://github.com/catwilo/streaming)
Self-hosted game and desktop streaming with Sunshine + Moonlight on headless Linux. Production-grade orchestration with X11 management, watchdog, exponential backoff, and full start/stop/status controls.

### [qemu-debian-mac](https://github.com/catwilo/qemu-debian-mac)
Run a headless Debian VM on macOS via QEMU. Manages the VM through tmux, with installers, health checks, and recovery helpers. Bootstraps itself on the old Bash that ships with macOS.

### [wifi-setup](https://github.com/catwilo/wifi-setup)
Wi-Fi and USB tethering setup toolkit. Locks scanning to the associated frequency, disables background scans that cause drops, and manages network forwarding between interfaces.

### [rsync-folder](https://github.com/catwilo/rsync-folder)
Event-driven folder sync via rsync. Watches for file changes and mirrors them immediately — no polling, no cron. Supports multiple independent profiles running in parallel.

### [sftp-folder](https://github.com/catwilo/sftp-folder)
Share a local folder over SFTP with a single command, with locking to avoid conflicting sessions. Quick, secure file access between machines without a permanent server.

### [spfx-tool](https://github.com/catwilo/spfx-tool)
Reproducible SharePoint Framework (SPFx) development environment on Debian. Pins a known-good toolchain so the setup is consistent across machines and reinstalls.

### [nvim-setup](https://github.com/catwilo/nvim-setup)
Neovim setup and LSP configuration for terminal-first workflows. Reproducible install with version pinning and verification.

### [termux-setup](https://github.com/catwilo/termux-setup)
Termux environment bootstrap for Android — packages, zsh, plugins, dotfile links, and MPD. Includes zsh-setup (merged).

### [setup-mac](https://github.com/catwilo/setup-mac)
macOS environment setup — Homebrew, Nix, PATH management, and dotfile wiring.

### [wlab](https://github.com/catwilo/wlab)
WPA2 handshake capture and wireless lab toolkit. For your own networks or networks you are explicitly authorized to test.

### [neko](https://github.com/catwilo/neko)
Install packages by named groups. Define groups (dev, gui, rpi, …) and install whole categories at once instead of remembering individual package names.

### [neko-gba](https://github.com/catwilo/neko-gba)
Scaffold a complete GBA emulation project structure inside a Neko self-hosted browser environment.

### [persistent-container-podman](https://github.com/catwilo/persistent-container-podman)
Immutable container image with persistent app data. Bakes user setup into the image while keeping data on the host — reproducible environment, no drift.

### [toolbox](https://github.com/catwilo/toolbox)
Single-purpose utilities grouped by theme:
- **audio/** — volume and microphone toggles
- **display/** — screen, input, and window-manager helpers
- **desktop/** — notifications, fonts, workspace movers
- **files/** — filename and path helpers
- **system/** — host setup and maintenance
- **vm/** — local VM control (start, stop, force-stop)
- **misc/** — nmap wrapper, xev parser, game of life

---

## Stack

Most tools are written in POSIX shell for portability across Debian, Arch, Termux, and macOS — with Go, Rust, and TypeScript where they fit better. They favor safe defaults, clear output, and being re-runnable without surprises.
