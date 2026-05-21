# wifi-setup — Failover WiFi USB↔nativa sobre NetworkManager

Gestión estable de dos antenas WiFi (una USB, una nativa PCI) con:

- **NetworkManager** como gestor único (limpia dhcpcd / wpa_supplicant sueltos).
- **Banco de redes compartido**: las credenciales no se atan a una antena; cualquier
  antena puede usar cualquier red guardada.
- **Failover por Internet real** cada 20 s: si la red activa pierde salida real a
  Internet (no solo "link up"), barre tus redes guardadas de mejor a peor señal,
  primero en la antena USB y luego en la nativa.
- **Anclaje manual (pin) blando**: `wifi-connect <ssid>` fija una red aunque tenga
  peor señal; el failover no la cambia mientras funcione. Si pierde Internet, el
  ancla se libera sola y el failover busca otra.

## Instalación

```bash
tar -xzf wifi-setup.tar.gz
cd wifi-setup
sudo ./scripts/install.sh
```

El instalador limpia configuraciones previas en conflicto, deja NetworkManager
como gestor único, despliega en `/opt/wifi-setup`, instala el monitor de failover
(timer systemd cada 20 s) y siembra la primera red (Enter = `cursed`, pide la
contraseña). Es idempotente: re-ejecutarlo no rompe nada.

## Comandos

| Comando | Qué hace |
|---|---|
| `wifi-add [ssid]` | Añade red al banco (Enter = `cursed`), pide contraseña oculta. |
| `wifi-saved` | Lista el banco: prioridad, activa, anclada. |
| `wifi-list [usb\|native]` | Redes visibles ahora en el aire (escaneo en vivo). |
| `wifi-connect <ssid> [usb\|native]` | Conecta y **ancla** la red (manual lock). |
| `wifi-connect --auto` | Libera el ancla, vuelve al failover automático. |
| `wifi-status` | Estado de antenas, red activa, señal e Internet real. |
| `wifi-prefer [usb\|native]` | Fija/muestra la antena preferida. |
| `wifi-passwd <ssid>` | Cambia contraseña (confirmada, con rollback si falla). |
| `wifi-showpass <ssid>` | Muestra contraseña del llavero NM (con confirmación). |
| `wifi-rm <ssid>` | Borra una red del banco. |
| `wifi-failover <status\|test\|on\|off>` | Controla el monitor. |
| `wifi-panic` | Botón de pánico: reinicia NM y fuerza reconexión. |

## Desinstalación

```bash
sudo ./scripts/uninstall.sh         # quita herramientas y monitor
sudo rm -rf /opt/wifi-setup         # opcional: borra estado y logs
```

NetworkManager y tus redes guardadas se conservan.

## Tailscale (opcional)

El instalador pregunta al final si quieres instalar/configurar Tailscale. Es una
fase aislada: corre solo después de confirmar que el WiFi y tu SSH están estables,
y si algo falla ahí, tu red WiFi ya quedó OK.

- Instala vía el instalador oficial (detecta **ARM y x64** automáticamente) y
  habilita `tailscaled` al arranque.
- Configura este equipo como **nodo simple con Tailscale SSH**:
  `tailscale up --ssh --accept-dns=false`.
- **No usa MagicDNS** (`--accept-dns=false`), así no sobrescribe tu DNS.
- **No afecta a tu SSH local**: el `sshd` del puerto 22 sigue igual; Tailscale SSH
  escucha solo en `tailscale0` (IPs `100.x`). En la LAN entras como siempre; desde
  fuera, por la tailnet (cifrado WireGuard — seguro en wifi públicos).
- **Idempotente**: si ya está conectado no hace nada; si está caído reconecta; si
  falta, instala.

Autenticación: por **navegador** (recomendado, muestra una URL) o por **auth key**
de un solo uso (se pega en el momento; no se guarda en disco, log ni `ps`).
Reconfigura con `wifi-tailscale setup`; estado con `wifi-tailscale status`.

### Si en el futuro quieres más de Tailscale

- **Llegar a otros dispositivos de tu LAN desde fuera**: *subnet router* con
  `tailscale up --advertise-routes=192.168.x.0/24` (aprueba la ruta en el admin).
- **Usar este equipo como salida a Internet** (VPN casera): `--advertise-exit-node`.
- **Alcanzar redes que comparten otros nodos**: `--accept-routes`.

## Arquitectura (por qué dos capas)

La preferencia de prioridad de NetworkManager decide *qué red* dentro de *una
antena*, pero **no** decide entre antena USB y nativa (NM trata cada dispositivo
por separado). Por eso la preferencia USB→nativa la orquesta el monitor de
failover, mientras que el orden por señal dentro de cada antena lo aporta NM.
La inactiva se apaga con `ip link set down` (no rfkill), para que NM pueda
reactivarla al instante si la activa cae.
