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

# Substitute environment variables in configs
envsubst < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
envsubst < /etc/stunnel/stunnel.conf.template > /etc/stunnel/stunnel.conf

# Start stunnel
stunnel4 /etc/stunnel/stunnel.conf

# Low-latency encoding params (GOP and bufsize; fallback script uses same via env)
GOP_SIZE="${GOP_SIZE:-30}"
BUF_SIZE="${BUF_SIZE:-4500k}"
export GOP_SIZE BUF_SIZE

# Trigger initial Fallback Feeder FIRST so Master has data from the start
# MUST run as www-data to match other scripts; pass env for FALLBACK_VIDEO and latency params
echo "Starting initial Fallback Feeder..."
su -s /bin/bash -c "export FALLBACK_VIDEO=\"$FALLBACK_VIDEO\"; export GOP_SIZE=\"$GOP_SIZE\"; export BUF_SIZE=\"$BUF_SIZE\"; /scripts/start_fallback.sh 'initial'" www-data &
sleep 2

# Start the MASTER STREAMER (Persistent connection to Kick)
# Listens on UDP (MPEG-TS), pushes to Stunnel -> Kick. Reduced fifo_size for lower latency.
echo "Starting Master Streamer (UDP Listener)..."
while true; do
    ffmpeg -y -loglevel warning -f mpegts -re -i "udp://127.0.0.1:10000?fifo_size=150000&overrun_nonfatal=1" \
        -c copy \
        -f flv "rtmp://127.0.0.1:19350/app/$KICK_STREAM_KEY" >/var/log/nginx/master.log 2>&1
    echo "Master Streamer crashed. Log content:"
    tail -n 10 /var/log/nginx/master.log
    sleep 1
done &

# Start the Live Push Listener (Wait for Nginx to push OBS stream here)
echo "Starting Live Push Listener..."
while true; do
    ffmpeg -y -listen 1 -i rtmp://127.0.0.1:1936/live/stream \
        -vf scale=1920:1080 \
        -c:v libx264 -preset veryfast -b:v 4500k -maxrate 4500k -bufsize "${BUF_SIZE}" -pix_fmt yuv420p -g "${GOP_SIZE}" -tune zerolatency \
        -c:a aac -b:a 160k -ar 44100 \
        -f mpegts "udp://127.0.0.1:10000?pkt_size=1316" > /var/log/nginx/live_listener.log 2>&1
    echo "Live Listener finished (stream ended), restarting loop..."
    sleep 1
done &

echo "Starting Nginx..."
nginx -g "daemon off;" || {
    echo "Nginx failed to start! Keeping container alive for debugging..."
    tail -f /dev/null
}
