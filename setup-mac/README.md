# setup-mac

Idempotent bootstrap for a fresh macOS client: detects Nix state, repairs a
broken Nix install, installs pinned packages, and wires `PATH` for
non-interactive shells.

## Why

A partial/aborted Nix install on macOS leaves an APFS `Nix Store` volume, two
`org.nixos.*` LaunchDaemons, and a `synthetic.conf` entry — but an empty
`/nix/store`. Tools then fall back to slow paths (e.g. `noemap` degrading to a
full `nc` subnet sweep because `nmap` is missing), which looks like a hang.
`setup-mac` detects that state, cleans it safely, and installs a healthy Nix.

## Layout

| File             | Role                                                       |
|------------------|------------------------------------------------------------|
| `setup.sh`       | Orchestrator: detect → ensure Nix → packages → PATH        |
| `repair-nix.sh`  | Clean a **broken** Nix install (gated, per-step `yes`)     |
| `versions.env`   | Single source of truth: installer URL, package list        |
| `lib/nix.sh`     | `classify_nix_state` → `absent` / `broken` / `healthy`     |
| `lib/deps.sh`    | `ensure_nix`, `ensure_packages`                            |
| `lib/path.sh`    | `ensure_path_zshenv` (non-interactive shells read .zshenv) |

## Usage

```sh
./setup.sh            # safe to re-run; refuses if Nix is broken
./repair-nix.sh       # only when state is broken; reboot after; then setup.sh
```

`repair-nix.sh` snapshots current infra to `state/` before any change, and
gates every destructive step (daemon removal, synthetic.conf/fstab edits,
APFS volume deletion) behind an explicit `yes`. The volume is deleted by
name (`Nix Store`), never by device id.

## Notes

- macOS-only (guards on `uname`).
- Nix installed via the Determinate Systems installer (robust APFS handling,
  clean uninstall).
- `PATH` guard targets `~/.zshenv` because `ssh host 'cmd'` spawns a
  non-interactive zsh that does **not** read `~/.zshrc`.
