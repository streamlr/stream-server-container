# AGENTS.md – Kick Stream Server with Fallback

## Propósito

Servidor de streaming en Docker para **Kick**. Recibe RTMP desde OBS (o similar), reenvía a Kick por RTMPS y, cuando la señal de OBS se corta, cambia automáticamente a un **video de fallback** (o video negro) sin cerrar la conexión con Kick.

## Stack

- **Docker** + **Docker Compose**
- **Nginx** con módulo **RTMP** (ingest y push interno)
- **FFmpeg** (transcodificación, fallback, enlace UDP → RTMP)
- **Stunnel** (RTMP sobre TLS hacia Kick)
- Shell (sh/bash) y configs; sin Node/Python

## Estructura de archivos

| Archivo                     | Rol                                                                                                                                         |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `entrypoint.sh`             | Orden de arranque: validación env, envsubst (nginx + stunnel), stunnel, fallback inicial, Master Streamer, Live Listener, Nginx             |
| `scripts/start_fallback.sh` | Alimenta UDP 10000 con `FALLBACK_VIDEO` o video negro (lavfi); bucle de reintento; guarda PID en `/tmp/feeder.pid`                          |
| `scripts/stop_fallback.sh`  | Mata el fallback por PID (`/tmp/feeder.pid`) y por patrón; llamado por Nginx al conectar OBS                                                |
| `nginx.conf`                | Template Nginx HTTP + RTMP: app `live` en 1935, `exec_publish` → stop_fallback, `exec_publish_done` → start_fallback, push a 127.0.0.1:1936 |
| `stunnel.conf.template`     | Template Stunnel; `connect = ${KICK_STREAM_HOST}:443`; se genera con envsubst                                                               |
| `docker-compose.yml`        | Build, puerto 1935, volúmenes `./assets`, `./nginx.conf` como template, env, healthcheck                                                    |
| `Dockerfile`                | Ubuntu 24.04, nginx, ffmpeg, libnginx-mod-rtmp, stunnel4, gettext-base, procps, netcat-openbsd                                              |
| `.env.example`              | Ejemplo de `KICK_STREAM_URL`, `KICK_STREAM_KEY`, `FALLBACK_VIDEO`, opcional `KICK_STREAM_HOST`                                              |

## Flujo de señal

1. **Arranque:** Fallback (o video negro) escribe MPEG-TS en **UDP 127.0.0.1:10000**. El **Master Streamer** lee ese UDP y envía FLV a **Stunnel** (127.0.0.1:19350) → Kick (RTMPS).
2. **OBS publica** a `rtmp://host:1935/live/stream` → Nginx ejecuta **exec_publish** → `stop_fallback.sh` (mata fallback). Nginx hace **push** a `rtmp://127.0.0.1:1936/live/stream`.
3. El **Live Push Listener** (FFmpeg en entrypoint) está en listen en 1936; al recibir el push, convierte RTMP → MPEG-TS y escribe en UDP 10000. Solo él escribe en UDP 10000 mientras OBS está conectado.
4. **OBS desconecta** → Nginx **exec_publish_done** → `start_fallback.sh` → fallback vuelve a escribir en UDP 10000.

Solo **un** proceso debe escribir en UDP 10000 en cada momento (fallback o Live Listener).

## Variables de entorno

- **KICK_STREAM_KEY** (obligatorio): clave de stream de Kick; usada en la URL RTMP hacia stunnel.
- **KICK_STREAM_URL** (recomendado): URL RTMPS de Kick; el entrypoint extrae el host para Stunnel si no se define `KICK_STREAM_HOST`.
- **KICK_STREAM_HOST** (opcional): host para Stunnel (ej. `xxx.global-contribute.live-video.net`). Si no se define, se deriva de `KICK_STREAM_URL`.
- **FALLBACK_VIDEO**: ruta del video de fallback (por defecto `/assets/fallback.mp4`). Si no existe el archivo, se usa video negro (lavfi).
- **GOP_SIZE**, **BUF_SIZE** (opcionales): GOP y bufsize para FFmpeg (low latency); por defecto 30 y 4500k.

## Cómo probar cambios

- Build y run: `docker compose up --build` (o `-d` en segundo plano).
- Simular OBS: `ffmpeg -re -i input.mp4 -c copy -f flv rtmp://localhost:1935/live/stream`
- Logs: `docker logs -f kick-stream-server`. Logs de fallback/Live/Master en `/var/log/nginx/` y `/tmp/` dentro del contenedor.
- Healthcheck: Docker comprueba el puerto 1935 con `nc -z localhost 1935`.

## Puntos sensibles para el agente

- **Puerto UDP 10000** y **puerto 1936**: no cambiarlos sin actualizar entrypoint, scripts y (si aplica) nginx. Todo el pipeline depende de ellos.
- **Un solo escritor en UDP 10000**: la coordinación entre fallback y Live Listener se hace con `stop_fallback.sh` (mata por PID y pkill) y `exec_publish` / `exec_publish_done` de Nginx. No añadir otro proceso que escriba en 10000.
- **Scripts ejecutados por Nginx** (`exec_publish`, `exec_publish_done`) suelen correr como **www-data**; el fallback inicial se lanza con `su ... www-data` para que los pkill por usuario coincidan.
- **Latencia**: se redujo con `wait_key off` / `wait_video off` en Nginx, GOP 30, bufsize 4500k, `-tune zerolatency` y `fifo_size=150000` en el Master. Bajar más el fifo_size o el GOP puede aumentar underruns o incompatibilidades con Kick; documentar cambios en README o aquí.
