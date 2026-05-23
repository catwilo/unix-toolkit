# scripts

A working collection of command-line tools built to solve real problems on Linux, Termux (Android), and macOS systems — network discovery, secure file workflows, remote development environments, and system automation.

Each tool here started from a concrete need rather than an exercise. They run in production on my own machines and are written to be portable, safe to re-run, and clear to maintain. This document walks through what each one does and why it exists, starting with the most involved.

---

## noemap — LAN discovery and SSH device mapper

Finding and connecting to machines on a home or lab network usually means remembering IP addresses, editing SSH configs by hand, and re-checking what changed. noemap removes that friction: it scans the network, identifies which devices are reachable over SSH, recognizes the operating system behind each one, and lets you reach any of them by a short name you choose once.

It was built to work the same way on a full Debian workstation and on a non-root Termux phone, deriving the right network interface automatically even on machines connected to several networks at once.

**Highlights**
- Automatic interface selection from the active route, with a manual override.
- Fast, passive OS detection (Linux, macOS, Windows, Android/Termux) using signals already available during the scan; an optional deeper scan confirms ambiguous hosts.
- Friendly aliases (`d0`, `d1`, …) so connecting is `nssh d0` instead of typing credentials.
- Companion tools that reuse the same address book: copy a remote file, run scp or rsync, or mirror a remote command's output straight to your clipboard.

**Install**
```sh
./noemap/bin/noemap install   # links commands into your PATH, sets up shell helpers
exec zsh                       # reload the shell
```

**Use**
```sh
noemap                 # scan and list reachable devices, then register new ones
noemap --deep          # add precise OS detection (asks for sudo once, up front)
noemap -i wlan0        # force a specific network interface
nssh d0                # open a shell on device "d0"
nclip d0:/etc/hostname # copy a remote file to your clipboard
```

---

## aicli — multi-account AI runtime from the terminal

A containerized setup for driving several AI assistants (Claude, ChatGPT, Gemini) from one terminal interface, with separate browser workers per account and an orchestration layer to coordinate them. Built on Podman with reproducible container definitions, so the whole environment comes up the same way on any machine.

**Install**
```sh
./aicli/scripts/setup.sh
./aicli/scripts/build-all.sh
```

**Use**
```sh
podman play kube aicli/podman/compose.yaml   # bring up the pod
aicli                                        # the CLI entrypoint
```

---

## qemu-debian-mac — run a Debian VM on macOS

Runs a headless QEMU Debian virtual machine on macOS, managed through tmux, with installers, health checks, and recovery helpers. It bootstraps itself cleanly even on the older Bash that ships with macOS, then re-runs under a modern shell — so it works out of the box without the user fixing their environment first. A GUI mode is available through XQuartz.

**Install & use**
```sh
./qemu-debian-mac/install.sh
qemu-debian-mac                 # start the VM (headless)
qemu-debian-mac gui             # start with GUI (XQuartz)
qemu-debian-mac/healthchecks/vm-health.sh
```

---

## clipso — copy anything to your clipboard, anywhere

Copying text to the clipboard sounds trivial until you are on a remote server over SSH, or on a phone, or in a terminal multiplexer — each needs a different mechanism. clipso detects the environment and picks the right one, falling back to a universal method that works even through an SSH session, so the content lands on the machine you are actually sitting at.

**Targets:** Termux (non-root), Debian, Arch Linux.

**Use**
```sh
clipso file.txt                 # copy a local file
clipso user@host:/path/file     # copy a remote file over SSH
echo "hello" | clipso           # copy piped input
```

---

## spfx-tool — reproducible SharePoint development environment

Setting up a SharePoint Framework (SPFx) development environment is notoriously version-sensitive. This tool pins and reproduces a known-good setup on Debian 13, so the environment is consistent every time instead of breaking on a mismatched Node or toolchain version.

**Install**
```sh
./spfx-tool/setup.sh
```

---

## rsync-folder — live folder synchronization

Keeps folders in sync as files change, event-driven, without polling or cron jobs. Supports multiple independent sync profiles at once, each watching its own folder.

**Use**
```sh
./rsync-folder/setup.sh
# configure a profile, then the watcher mirrors changes as they happen
```

---

## streaming — desktop and game streaming (Sunshine + Moonlight)

A production-ready setup for streaming a headless Linux desktop to another device: Sunshine runs the host side (X11, window manager, and a watchdog that keeps it healthy), and Moonlight connects as the client. Wrapped with clear start/stop/status controls and a monitoring panel.

**Use**
```sh
./streaming/setup.sh
./streaming/run_sunshine.sh start    # host side
./streaming/run_moonlight.sh         # client side
```

---

## wifi-setup — reliable Wi-Fi association

An installer and toolkit for stabilizing Wi-Fi behavior — locking scanning to the associated frequency and disabling background scans that cause drops. Useful on machines where the default Wi-Fi behavior interrupts connectivity.

**Install**
```sh
./wifi-setup/install.sh
```

---

## persistent-container-podman — immutable image with persistent app data

A container build that bakes user setup and configuration into an immutable image, while keeping application data and config persistent on the host. The goal is a reproducible environment where the system layer never drifts but your data stays put.

**Use**
```sh
podman build -t myenv persistent-container-podman/
podman compose -f persistent-container-podman/compose_appen.yml up
```

---

## neko — install packages by named groups

Installs packages grouped by purpose — a "dev" group, an "x11" group, and so on — so setting up a new machine means installing whole categories at once instead of remembering individual package names. You define the groups and what goes in each, then install them by name.

**Use**
```sh
./neko/neko.sh dev        # install the "dev" group
./neko/addneko.sh         # manage what's in each group
```

---

## wlab — WPA2 handshake capture (educational / authorized use only)

> ⚠️ For your own networks or networks you are explicitly authorized to test. Built as a learning tool for understanding Wi-Fi security.

A guided tool for capturing WPA2 handshakes in a lab setting, used to study how wireless authentication works and how to assess the security of networks you own.

---

## rwxdir-scan — find world-writable-and-executable paths

Scans the filesystem for paths carrying full read-write-execute permissions — the kind of loose permissions that are easy to create by accident and can become a security risk. Useful for auditing a system and tightening it up.

**Use**
```sh
./rwxdir/rwxdir-scan
```

---

## sftp-folder — share a folder over SFTP

Shares a local folder over SFTP with a single command, with locking to avoid conflicting sessions. Handy for quick, secure file access between machines without setting up a permanent server.

**Use**
```sh
./sftp-folder/sftp-folder.sh
```

---

## neko-gba — scaffold a project structure

Creates a complete project structure under `~/neko-gba` in one step, so a new project starts from a consistent layout instead of being assembled by hand.

**Use**
```sh
./neko-gba/neko-gba-setup.sh
```

---

## Smaller utilities

Single-purpose helpers, grouped by theme into their own folders:

- **`audio/`** — volume and microphone toggles (`vol`, `toggle-vol`, `toggle-mic`).
- **`display/`** — screen, input, and window-manager helpers (`setscreen`, `xrandr-Virtual.sh`, `reset-mouse.sh`, `wacom`, `set-i3-gaps.sh`, `fehbg`).
- **`vm/`** — local VM control: start, graceful stop, force-stop (`a.on`, `a.off`, `a.foff`).
- **`desktop/`** — notifications, fonts, workspace movers (`deadd.sh`, `notifydeadd`, `choose-font-alacritty.sh`, `moveWorkspace.sh`, `renameWorkspace.sh`, `press_e.sh`, `xcolor`).
- **`files/`** — filename and path helpers (`fixsuffix.sh`, `mv-depth.sh`).
- **`system/`** — host setup and maintenance (`rpi-optimize.sh`, `reset-iwd.service.sh`, `setup-mpd-termux.sh`, `zsh_plugins_setup.sh`, `run-java.sh`, `lan-connection-lan2lan`).
- **`misc/`** — assorted: `nmapAgresiveFasterOut.sh`, `xev-awk`, `game-of-life.py`.

---

## Notes

Most tools are written in POSIX shell for portability across Debian, Arch, Termux, and macOS, with a few in Go, Rust, and TypeScript where it fit better. They favor safe defaults, clear output, and being re-runnable without surprises.

This collection grows over time; entries are added and refined as the tools mature
