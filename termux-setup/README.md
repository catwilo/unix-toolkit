# termux-setup

Instalador idempotente del entorno zsh para Termux y Debian.

## Uso

```bash
bash setup.sh
bash setup.sh --dry-run
bash setup.sh --only=pkg
bash setup.sh --only=links
bash setup.sh --only=mpd
```

## Escalabilidad macOS

- Desbloquear macos en lib/detect.sh
- Implementar _pkg_macos en lib/pkg.sh
- Agregar packages/macos.env
