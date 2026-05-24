# nvim-setup

Reproducible Neovim IDE setup. LSP + completion + diagnostics for
TypeScript/React, SCSS/CSS, JSON, Lua. Pinned versions, snapshot/rollback,
binary resolution. Host-side (no container), clipboard via clipso (OSC52 + X11).

Neovim 0.12.x | Node 22 (nvm) | lazy.nvim | no mason

## Install

    bash ~/scripts/nvim-setup/setup.sh

Runs: snapshot -> plugin sync -> pinned npm servers -> binary resolution ->
lua-ls -> verify. If verify fails, auto-rolls back to the prior versions.

## Verify

    bash ~/scripts/nvim-setup/lib/verify.sh

## Versions and rollback

All versions pinned in versions.env (single source of truth).

    lib/state.sh show       current snapshot
    lib/state.sh snapshot   save current global versions
    lib/state.sh rollback   reinstall the snapshot exact versions

## Add a language

1. Add one entry to lib/servers.lua (cmd = the server binary name).
2. Add its npm package to NPM_LSP_SERVERS in versions.env (pinned).
3. Run setup.sh. The config enables a server only if its binary resolves.

## Keymaps (LSP)

gd definition, gr references, K hover, <leader>rn rename,
<leader>ca code action, [d / ]d prev/next diagnostic.
