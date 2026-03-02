#!/bin/sh

# Validate required environment
if [ -z "$KICK_STREAM_KEY" ]; then
    echo "Error: KICK_STREAM_KEY is not set. Set it in .env or environment." >&2
    exit 1
fi
if [ -z "$KICK_STREAM_URL" ] && [ -z "$KICK_STREAM_HOST" ]; then
    echo "Error: Either KICK_STREAM_URL or KICK_STREAM_HOST must be set." >&2
    exit 1
fi

# Derive KICK_STREAM_HOST from KICK_STREAM_URL if not set (e.g. rtmps://host:443/app/ -> host)
if [ -z "$KICK_STREAM_HOST" ] && [ -n "$KICK_STREAM_URL" ]; then
    KICK_STREAM_HOST=$(echo "$KICK_STREAM_URL" | sed -n 's|^[^/]*//\{0,1\}\([^:/]*\).*|\1|p')
    if [ -z "$KICK_STREAM_HOST" ]; then
        echo "Error: Could not parse host from KICK_STREAM_URL=$KICK_STREAM_URL" >&2
        exit 1
    fi
    export KICK_STREAM_HOST
fi

# Stream key for Nginx RTMP app path (used in push URL)
export STREAM_KEY=${STREAM_KEY:-stream}

# Substitute environment variables in configs
envsubst < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
envsubst < /etc/stunnel/stunnel.conf.template > /etc/stunnel/stunnel.conf

# Start stunnel
stunnel4 /etc/stunnel/stunnel.conf

# Low-latency encoding params (GOP, bitrate, bufsize, preset; fallback script uses same via env)
# GOP más bajo (15) = más keyframes = recuperación más rápida en movimientos bruscos
GOP_SIZE="${GOP_SIZE:-15}"
FFMPEG_BITRATE="${FFMPEG_BITRATE:-10000k}"
FFMPEG_BUFSIZE="${FFMPEG_BUFSIZE:-20000k}"
FFMPEG_PRESET="${FFMPEG_PRESET:-veryfast}"
BUF_SIZE="${BUF_SIZE:-$FFMPEG_BUFSIZE}"
# UDP buffer: más alto = menos caídas/tearing en movimientos bruscos (default 5M para gaming)
UDP_FIFO_SIZE="${UDP_FIFO_SIZE:-5000000}"
# Output framerate (match OBS: 60 for gaming, 30 for lower bandwidth)
STREAM_FPS="${STREAM_FPS:-60}"
# Debounce antes de iniciar fallback cuando OBS desconecta (evita flicker en reconexiones breves)
FALLBACK_DELAY="${FALLBACK_DELAY:-0.5}"
export GOP_SIZE BUF_SIZE FFMPEG_BITRATE FFMPEG_BUFSIZE FFMPEG_PRESET UDP_FIFO_SIZE STREAM_FPS FALLBACK_DELAY

# #region agent log
# Create debug log before any www-data script runs; 666 = writable by root and www-data
DEBUG_LOG="${DEBUG_LOG:-/workspace/debug-d2f761.log}"
touch "${DEBUG_LOG}" 2>/dev/null && chmod 666 "${DEBUG_LOG}" 2>/dev/null || true
export DEBUG_LOG
# #endregion

# Trigger initial Fallback Feeder FIRST so Master has data from the start
# MUST run as www-data to match other scripts; pass env for FALLBACK_VIDEO and latency params
echo "Starting initial Fallback Feeder..."
su -s /bin/bash -c "export FALLBACK_VIDEO=\"$FALLBACK_VIDEO\"; export GOP_SIZE=\"$GOP_SIZE\"; export BUF_SIZE=\"$BUF_SIZE\"; export FFMPEG_BITRATE=\"$FFMPEG_BITRATE\"; export FFMPEG_PRESET=\"$FFMPEG_PRESET\"; export STREAM_FPS=\"$STREAM_FPS\"; export DEBUG_LOG=\"$DEBUG_LOG\"; /scripts/start_fallback.sh 'initial'" www-data &
sleep 2

# Start the MASTER STREAMER (Persistent connection to Kick)
# Listens on UDP (MPEG-TS), pushes to Stunnel -> Kick. fifo_size absorbs underruns (tearing/banding).
echo "Starting Master Streamer (UDP Listener)..."
sleep 3
while true; do
    # #region agent log
    _ts=$(date +%s)000; echo "{\"sessionId\":\"d2f761\",\"runId\":\"master\",\"hypothesisId\":\"A\",\"location\":\"entrypoint.sh:Master\",\"message\":\"Master Streamer starting\",\"data\":{},\"timestamp\":$_ts}" >> "${DEBUG_LOG}" 2>/dev/null || true
    # #endregion
    # No -re: input is already a live UDP stream. Larger fifo_size = fewer underruns en movimientos bruscos.
    ffmpeg -y -loglevel warning \
        -thread_queue_size 4096 \
        -f mpegts -i "udp://127.0.0.1:10000?fifo_size=${UDP_FIFO_SIZE}&overrun_nonfatal=1" \
        -c copy \
        -f flv -flvflags no_duration_filesize "rtmp://127.0.0.1:19350/app/$KICK_STREAM_KEY" >/var/log/nginx/master.log 2>&1
    _exit=$?
    # #region agent log
    _ts=$(date +%s)000; echo "{\"sessionId\":\"d2f761\",\"runId\":\"master\",\"hypothesisId\":\"A\",\"location\":\"entrypoint.sh:Master\",\"message\":\"Master Streamer exited\",\"data\":{\"exitCode\":$_exit},\"timestamp\":$_ts}" >> "${DEBUG_LOG}" 2>/dev/null || true
    # #endregion
    echo "Master Streamer crashed. Log content:"
    tail -n 10 /var/log/nginx/master.log
    sleep 1
done &

# Start the Live Push Listener (Wait for Nginx to push OBS stream here)
echo "Starting Live Push Listener..."
while true; do
    # Listen on localhost:1936. When Nginx pushes, this wakes up. Uses STREAM_KEY to match nginx push path.
    # thread_queue_size: buffer para picos de OBS (movimientos bruscos). -vsync cfr: framerate constante.
    ffmpeg -y -loglevel warning \
        -thread_queue_size 4096 -listen 1 -i "rtmp://127.0.0.1:1936/live/${STREAM_KEY}" \
        -vf "scale=1920:1080,fps=${STREAM_FPS}" \
        -c:v libx264 -preset "${FFMPEG_PRESET}" -b:v "${FFMPEG_BITRATE}" -maxrate "${FFMPEG_BITRATE}" -bufsize "${FFMPEG_BUFSIZE}" -pix_fmt yuv420p -g "${GOP_SIZE}" -tune zerolatency \
        -c:a aac -b:a 160k -ar 44100 \
        -vsync cfr -f mpegts "udp://127.0.0.1:10000?pkt_size=1316" > /var/log/nginx/live_listener.log 2>&1
    # #region agent log
    _ts=$(date +%s)000; echo "{\"sessionId\":\"d2f761\",\"runId\":\"live_listener\",\"hypothesisId\":\"D\",\"location\":\"entrypoint.sh:LiveListener\",\"message\":\"Live Listener finished (OBS disconnected?)\",\"data\":{},\"timestamp\":$_ts}" >> "${DEBUG_LOG}" 2>/dev/null || true
    # #endregion
    echo "Live Listener finished (stream ended), restarting loop..."
    sleep 1
done &

echo "Starting Nginx..."
nginx -g "daemon off;" || {
    echo "Nginx failed to start! Keeping container alive for debugging..."
    tail -f /dev/null
}
