#!/bin/sh

# Substitute environment variables in nginx.conf
envsubst < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Start stunnel
stunnel4 /etc/stunnel/stunnel.conf

# Start the MASTER STREAMER (Persistent connection to Kick)
# Listens on UDP (MPEG-TS), pushes to Stunnel -> Kick
echo "Starting Master Streamer (UDP Listener)..."
while true; do
    ffmpeg -y -loglevel warning -f mpegts -re -i "udp://127.0.0.1:10000?fifo_size=5000000&overrun_nonfatal=1" \
        -c copy \
        -f flv "rtmp://127.0.0.1:19350/app/$KICK_STREAM_KEY" >/var/log/nginx/master.log 2>&1
    echo "Master Streamer crashed. Log content:"
    tail -n 10 /var/log/nginx/master.log
    sleep 1
done &

# Trigger initial Fallback Feeder
# MUST run as www-data to match other scripts
echo "Starting initial Fallback Feeder..."
su -s /bin/bash -c "/scripts/start_fallback.sh 'initial'" www-data &

# Start the Live Push Listener (Wait for Nginx to push OBS stream here)
echo "Starting Live Push Listener..."
while true; do
    # Listen on localhost:1936. When Nginx pushes, this wakes up.
    # Convert incoming RTMP to MPEG-TS UDP for the master.
        ffmpeg -y -listen 1 -i rtmp://127.0.0.1:1936/live/stream \
            -vf scale=1920:1080 \
            -c:v libx264 -preset "${FFMPEG_PRESET:-superfast}" -b:v "${FFMPEG_BITRATE:-6000k}" -maxrate "${FFMPEG_BITRATE:-6000k}" -bufsize "${FFMPEG_BUFSIZE:-12000k}" -pix_fmt yuv420p -g 60 \
            -c:a aac -b:a 128k -ar 44100 \
            -f mpegts "udp://127.0.0.1:10000?pkt_size=1316" > /var/log/nginx/live_listener.log 2>&1
    
    echo "Live Listener finished (stream ended), restarting loop..."
    sleep 1
done &

echo "Starting Nginx..."
nginx -g "daemon off;" || {
    echo "Nginx failed to start! Keeping container alive for debugging..."
    tail -f /dev/null
}
