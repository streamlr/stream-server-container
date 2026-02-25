# Kick Stream Server with Fallback 🚀

Este proyecto proporciona un servidor de streaming en Docker que garantiza que tu stream en Kick **nunca se caiga**. Utiliza Nginx-RTMP para recibir tu señal (desde OBS, vMix, etc.) y FFmpeg para reenviarla a Kick.

Si tu señal de origen se interrumpe, el servidor cambia automáticamente a un video de **fallback** (fondo) sin cerrar la conexión con Kick.

## Requisitos

- [Docker](https://www.docker.com/)
- [Docker Compose](https://docs.docker.com/compose/)
- Una cuenta de Kick con Stream URL y Stream Key.

## Recursos VPS

| Nivel           | CPU      | RAM    | FPS | Bitrate recomendado | Preset recomendado        |
| --------------- | -------- | ------ | --- | ------------------- | ------------------------- |
| **Mínimo**      | 1–2 vCPU | 1 GB   | 30  | 4500k–6000k         | `superfast` o `ultrafast` |
| **Recomendado** | 2–4 vCPU | 2–4 GB | 60  | 6000k–8000k         | `veryfast`                |
| **Óptimo**      | 4+ vCPU  | 4+ GB  | 60  | 8000k–12000k        | `veryfast` o `fast`       |

Configura `FFMPEG_BITRATE`, `FFMPEG_PRESET` y `STREAM_FPS` en tu `.env` según el nivel de tu VPS. Si el stream va a tirones o la CPU va al 100%, baja el bitrate, reduce los FPS (ej. 30) o usa un preset más rápido (`ultrafast` < `superfast` < `veryfast` < `fast`).

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
5.  **Bandas horizontales / tearing** (opcional): Si el stream se ve "glitcheado" o con bandas, aumenta el buffer UDP:
    ```env
    UDP_FIFO_SIZE=1000000     # Default. Prueba 5000000 o 10000000 si persiste
    STREAM_FPS=60             # Debe coincidir con OBS (60 para gaming, 30 para ahorrar)
    ```
6.  **Cortes entre OBS y fallback** (opcional): Si el stream parpadea entre tu señal y el fallback, aumenta el debounce. Si el fallback tarda en aparecer, bájalo o ponlo a 0:
    ```env
    FALLBACK_DELAY=0.5        # Segundos antes de activar fallback (default 0.5). 0 = inmediato. Más alto = menos parpadeo
    ```

## Uso

1.  **Levantar el servidor**:
    ```bash
    docker compose up -d --build
    ```
2.  **Configurar OBS**:
    - **Codificador**: x264 o NVIDIA NVENC H.264
    - **Tasa de bits**: La misma que `FFMPEG_BITRATE` en tu `.env` (ej. 8000 para `8000k`)
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
