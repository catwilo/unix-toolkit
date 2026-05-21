# spfx-tool

Reproducible SPFx development environment for Debian 13 (trixie).
Rootless Podman. No root. Survives upgrades.

SPFx 1.22.x · Node 22 LTS · Heft · x86_64

---

## Quickstart

```bash
# 1. Extract and run setup — único paso de instalación
bash spfx-tool/setup.sh

# 2. Recargar PATH (o abrir terminal nueva)
source ~/.bashrc

# 3. Verificar entorno
spfx-verify

# 4. Crear primer proyecto
spfx-new room-booking-dashboard react-webpart
```

> `setup.sh` copia los archivos a `~/dev/spfx/`, construye la imagen Podman y configura el PATH. Es idempotente — se puede re-ejecutar sin problema.

---

## Comandos

| Comando | Descripción |
|---|---|
| `spfx-bootstrap` | Instalar/reparar entorno |
| `spfx-new <nombre> [preset]` | Scaffoldear proyecto |
| `spfx-dev <nombre>` | Dev server (Podman) |
| `spfx-build <nombre>` | Build producción → `.sppkg` |
| `spfx-smoke [nombre]` | Crea + empaqueta un webpart real → `.sppkg` desplegable |
| `spfx-shell [nombre]` | Shell interactivo del contenedor |
| `spfx-verify` | Verificar todos los checks del entorno |
| `spfx-test [--fixture <tipo>]` | Smoke tests |
| `spfx-upgrade --node <v>` | Upgrade controlado de versiones |

---

## Presets

Scaffolding no-interactivo via archivos de configuración versionados en `lib/presets/`:

| Preset | Tipo |
|---|---|
| `react-webpart` | React web part |
| `extension` | Application customizer |
| `library` | Library component |
| `ace` | Adaptive card extension |
| `interactive` | Prompts Yeoman (default) |

```bash
spfx-new room-booking-dashboard react-webpart   # no-interactivo
spfx-new my-app                                 # Yeoman interactivo
```

---

## Requisito previo: directorio del proyecto

`spfx-shell <nombre>` y `spfx-dev <nombre>` requieren que el proyecto ya exista:

```bash
# Correcto — el directorio existe porque spfx-new lo creó
spfx-new room-booking-dashboard react-webpart
spfx-shell room-booking-dashboard

# Error — el directorio no existe todavía
spfx-shell room-booking-dashboard   # ← falla si no se corrió spfx-new antes
```

---

## Reconstruir imagen tras cambios en Containerfile

Si se modifica `lib/Containerfile`, la imagen cacheada queda obsoleta. Reconstruir:

```bash
podman image rm localhost/spfx-dev:latest
spfx-bootstrap --skip-verify
```

`--skip-verify` omite los checks post-build para ir más rápido. Correr `spfx-verify` al final si se quiere confirmar.

---

## Versiones

Todas las versiones están pinned en `versions.env`. Editar ahí — nunca hardcodear en otro lado.

```bash
spfx-upgrade --node 22 --spfx 1.22.2   # upgrade controlado
spfx-upgrade --node 22 --dry-run        # preview sin aplicar
```

Los upgrades hacen snapshot de `versions.env` antes de aplicar y auto-rollback en fallo.

---

## CI / Automatización

```bash
ci/run.sh               # lint + verify + smoke tests
ci/run.sh --lint-only   # solo análisis estático
ci/run.sh --no-tests    # lint + verify sin tests
```

Requiere `shellcheck` y `shfmt` para análisis estático completo:
```bash
apt-get install shellcheck
# shfmt: https://github.com/mvdan/sh/releases
```

---

## Arquitectura

```
Debian 13 (host)
└── Podman rootless
    └── spfx-dev image (Node 22 LTS)
        └── yo / @microsoft/generator-sharepoint / heft / gulp-cli
            └── /workspace → ~/dev/spfx/projects/<nombre>

~/dev/spfx/
├── versions.env          ← fuente única de versiones
├── bin/                  ← comandos CLI (en PATH)
│   ├── spfx-bootstrap
│   ├── spfx-new
│   ├── spfx-dev
│   ├── spfx-build
│   ├── spfx-smoke
│   ├── spfx-shell
│   ├── spfx-verify
│   ├── spfx-test
│   └── spfx-upgrade
├── lib/
│   ├── core.sh           ← logging, validación, primitivas de entorno
│   ├── runtime.sh        ← abstracción de ejecución Podman
│   ├── presets.sh        ← scaffolding declarativo
│   └── presets/          ← JSONs de presets versionados
├── projects/             ← workspaces de proyectos (bind-mount a /workspace)
├── logs/                 ← logs con timestamp de todas las operaciones
├── fixtures/             ← proyectos de test congelados
└── ci/
    └── run.sh            ← pipeline CI
```

---

## Matriz de compatibilidad Node/SPFx

| SPFx | Node 18 | Node 20 | Node 22 |
|---|---|---|---|
| 1.20.x | ✔ | | |
| 1.21.x | ✔ | ✔ | |
| 1.22.x | ✔ | ✔ | ✔ |

`spfx-upgrade` valida esta matriz antes de aplicar cambios.

---

## Troubleshooting

```bash
spfx-verify               # revisar todos los componentes
spfx-bootstrap            # reparar instalación
spfx-shell                # inspeccionar entorno del contenedor
cat ~/dev/spfx/logs/*.log # logs detallados
```

Debug output:
```bash
SPFX_DEBUG=1 spfx-build my-app
```
