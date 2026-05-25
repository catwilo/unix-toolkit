#!/usr/bin/env bash
# path.sh — ensure Nix + ~/.local/bin are on PATH for NON-INTERACTIVE shells.
#
# Problem: macOS zsh non-login/non-interactive shells (what `ssh host cmd`
# spawns) read ONLY ~/.zshenv, not ~/.zshrc. Tools installed under Nix or
# ~/.local/bin are invisible to `nssh d1 '<cmd>'` unless .zshenv sets PATH.
# This is why `noemap` and `nix` were "not found" over SSH.

ensure_path_zshenv() {
    local zshenv="$HOME/.zshenv"
    local marker="# >>> setup-mac PATH >>>"
    if [ -f "$zshenv" ] && grep -qF "$marker" "$zshenv"; then
        ok "PATH guard already in ~/.zshenv"
        return 0
    fi
    info "adding PATH guard to ~/.zshenv (non-interactive shells)"
    {
        printf '\n%s\n' "$marker"
        # Nix daemon profile (single- or multi-user layouts)
        printf '%s\n' 'if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then'
        printf '%s\n' '  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        printf '%s\n' 'fi'
        # user-local bin
        printf '%s\n' 'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac'
        printf '%s\n' "# <<< setup-mac PATH <<<"
    } >> "$zshenv"
    ok "~/.zshenv updated"
}
