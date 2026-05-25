# plugins.sh — verify .addons-zsh plugins exist in custom_termux
# Requires: core.sh
# Plugins are embedded in custom_termux repo — no upstream clone needed

PLUGINS_DIR="${CUSTOM_TERMUX_DIR:-$HOME/custom_termux}/.addons-zsh"

REQUIRED_PLUGINS="
fzf
fzf-tab
zsh-autosuggestions
fast-syntax-highlighting
aliass
"

verify_plugins() {
  step "Verificando plugins"
  local missing=0
  for plugin in $REQUIRED_PLUGINS; do
    [ -z "$plugin" ] && continue
    if [ -d "$PLUGINS_DIR/$plugin" ]; then
      ok "plugin: $plugin"
    else
      err "plugin faltante: $plugin"
      missing=$((missing + 1))
    fi
  done
  [ "$missing" -gt 0 ] && die "$missing plugin(s) faltantes en $PLUGINS_DIR"
}
