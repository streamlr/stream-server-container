# Kick Stream Server with Fallback 🚀

Este proyecto proporciona un servidor de streaming en Docker que garantiza que tu stream en Kick **nunca se caiga**. Utiliza Nginx-RTMP para recibir tu señal (desde OBS, vMix, etc.) y FFmpeg para reenviarla a Kick.

Si tu señal de origen se interrumpe, el servidor cambia automáticamente a un video de **fallback** (fondo) sin cerrar la conexión con Kick.

## Requisitos

- [Docker](https://www.docker.com/)
- [Docker Compose](https://docs.docker.com/compose/)
- Una cuenta de Kick con Stream URL y Stream Key.

## Configuración Rápida

1.  **Clonar/Descargar** los archivos en una carpeta.
2.  **Configurar credenciales**:
    Copia el archivo de ejemplo:
    ```bash
    cp .env.example .env
    ```
    Edita `.env` y añade tus datos de Kick:
    ```env
    KICK_STREAM_URL=rtmps://tu-servidor-de-kick
    KICK_STREAM_KEY=sk_tu-clave-de-retransmision
    ```
3.  **Video de Fallback**:
    Coloca un video llamado `fallback.mp4` en la carpeta `assets/` (o configura `FALLBACK_VIDEO` en `.env`). Si el archivo no existe, el servidor generará automáticamente video negro con silencio para que la conexión con Kick no se corte.
4.  **Calidad de video** (opcional): Si la imagen se ve pixelada, ajusta en `.env`:
    ```env
    FFMPEG_BITRATE=8000k      # Bitrate (por defecto 8000k para 1080p)
    FFMPEG_BUFSIZE=16000k     # Buffer (suele ser 2× bitrate)
    FFMPEG_PRESET=veryfast    # veryfast, superfast, ultrafast (más rápido = menos calidad)
    ```

## Uso

1.  **Levantar el servidor**:
    ```bash
    docker compose up -d --build
    ```
2.  **Configurar OBS**:
    - **Servicio**: Personalizado
    - **Servidor**: `rtmp://localhost:1935/live` (o `rtmp://localhost:1935` si OBS pide servidor y app por separado)
    - **Clave de retransmisión**: `stream`

## Cómo funciona

- El servidor Docker está "siempre encendido", transmitiendo el video de fallback a Kick.
- Cuando empiezas a emitir desde OBS a `rtmp://localhost:1935/live/stream`, el servidor detecta la señal.
- Tu señal en vivo sustituye al video de fallback en el pipe hacia Kick.
- Si dejas de transmitir, el servidor vuelve a enviar el video de fallback (o video negro si no hay archivo); el proceso que envía datos a Kick no se detiene.

## Comandos Útiles

- **Ver logs en tiempo real**: `docker logs -f kick-stream-server`
- **Detener el servidor**: `docker compose down`
- **Reiniciar el servidor**: `docker compose restart`

---

Hecho con con fines de streaming ininterrumpido.
