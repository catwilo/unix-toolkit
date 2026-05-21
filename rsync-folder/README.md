# rsync-folder

Sincronización en vivo con rsync, event-driven, sin polling ni cron.  
Soporta múltiples perfiles simultáneos, cada uno con su propio watcher independiente.

## Instalar

    ./setup.sh

## Uso básico (perfil activo)

    rsync-folder watch              # watcher en foreground
    rsync-folder watch-bg           # watcher en background
    rsync-folder sync               # sync manual una sola vez
    rsync-folder status             # estado de todos los perfiles
    rsync-folder stop               # detener watcher activo
    rsync-folder tail               # ver log en vivo
    rsync-folder check              # diagnóstico completo

## Multi-perfil — varios orígenes y destinos simultáneos

Cada perfil tiene su propio watcher independiente.

    # Crear y configurar un segundo perfil
    rsync-folder profile new trabajo
    nano ~/.config/rsync-folder/profiles/trabajo.env

    # Arrancar watchers de múltiples perfiles simultáneamente
    rsync-folder watch-bg default   # watcher del perfil 'default'
    rsync-folder watch-bg trabajo   # watcher del perfil 'trabajo'

    # Ver estado de todos
    rsync-folder status             # muestra PID y estado de cada perfil

    # Sync manual de un perfil específico
    rsync-folder sync push trabajo

    # Detener un perfil específico
    rsync-folder stop trabajo

    # Detener todos
    rsync-folder stop

## Perfiles

    rsync-folder profile list                # listar perfiles + estado watcher
    rsync-folder profile show                # ver perfil activo
    rsync-folder profile show trabajo        # ver perfil específico
    rsync-folder profile new <nombre>        # crear perfil desde template
    rsync-folder switch <nombre>             # cambiar perfil activo (recarga watcher)

### Campos de un perfil (`profiles/<nombre>.env`)

| Variable             | Valores               | Descripción                                |
|----------------------|-----------------------|--------------------------------------------|
| `SOURCE`             | ruta absoluta         | Origen local                               |
| `DESTINATION`        | ruta o user@host:path | Destino local o remoto (SSH)               |
| `DIRECTION`          | push / pull / both    | Dirección de sincronización                |
| `DEBOUNCE_SEC`       | entero (default 3)    | Espera tras evento antes de sincronizar    |
| `MAX_RETRIES`        | entero (default 5)    | Reintentos ante fallo de rsync             |
| `RETRY_DELAY`        | entero (default 5)    | Segundos entre reintentos                  |
| `SSH_KEY`            | ruta absoluta         | Clave privada SSH (vacío = usar agente)    |
| `EXCLUDES_FILE`      | ruta                  | Lista de exclusiones (default: compartida) |
| `BACKUP_ON_OVERWRITE`| 0 / 1                 | Copia de seguridad antes de sobreescribir  |

## Clave SSH

    rsync-folder ssh-key show         # ver clave actual (ruta enmascarada)
    rsync-folder ssh-key set ~/.ssh/mi_clave  # configurar clave
    rsync-folder ssh-key test         # probar conexión

## Diagnóstico — si los archivos no se copian

1. Verificar que inotifywait esté instalado:

       rsync-folder check

2. Ver log en vivo mientras creas/editas un archivo:

       rsync-folder tail &
       touch /storage/emulated/0/Download/prueba.txt

3. Forzar sync manual para confirmar que rsync funciona:

       rsync-folder sync push

4. Revisar log de watcher específico:

       rsync-folder logs 50 default

## Compatibilidad

| Entorno   | Watcher       | Notas                                    |
|-----------|---------------|------------------------------------------|
| Termux    | inotifywait   | `pkg install inotify-tools rsync openssh`|
| Debian    | inotifywait   | `apt install inotify-tools rsync`        |
| macOS     | fswatch       | `brew install fswatch rsync`             |
| Linux sin inotify | fswatch | `apt install fswatch`               |

## Editar excludes

    nano $XDG_CONFIG_HOME/rsync-folder/excludes.txt

## Directorio de logs y datos

    ~/.config/rsync-folder/sync.log           # log de sincronizaciones
    ~/.config/rsync-folder/watcher-<p>.log    # log por perfil
    ~/.config/rsync-folder/sync-stats.tsv     # estadísticas
    ~/.config/rsync-folder/run/<p>.watcher.pid # PID por perfil
