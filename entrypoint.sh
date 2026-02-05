#!/bin/sh

# Substitute environment variables in nginx.conf
export STREAM_KEY=${STREAM_KEY:-stream}
envsubst < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Start stunnel
stunnel4 /etc/stunnel/stunnel.conf

# Start the MASTER STREAMER (Persistent connection to Kick)
# Listens on UDP (MPEG-TS), pushes to Stunnel -> Kick
echo "Starting Master Streamer (UDP Listener)..."
sleep 3
while true; do
    # REMOVED -re because the input is already a live UDP stream. 
    # Added thread_queue_size and tuned fifo_size for stability.
    ffmpeg -y -loglevel warning \
        -thread_queue_size 1024 \
        -f mpegts -i "udp://127.0.0.1:10000?fifo_size=10000000&overrun_nonfatal=1" \
        -c copy \
        -f flv -flvflags no_duration_filesize "rtmp://127.0.0.1:19350/app/$KICK_STREAM_KEY" >/var/log/nginx/master.log 2>&1
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
    # Added -tune zerolatency, CBR enforcement, and better buffer management.
    ffmpeg -y -listen 1 -i rtmp://127.0.0.1:1936/live/${STREAM_KEY} \
        -vf scale=1920:1080 \
        -c:v libx264 -preset "${FFMPEG_PRESET:-veryfast}" \
        -tune zerolatency \
        -b:v "${FFMPEG_BITRATE:-8000k}" \
        -minrate "${FFMPEG_BITRATE:-8000k}" \
        -maxrate "${FFMPEG_BITRATE:-8000k}" \
        -bufsize "${FFMPEG_BUFSIZE:-16000k}" \
        -pix_fmt yuv420p \
        -g 60 -keyint_min 60 -sc_threshold 0 \
        -x264-params "nal-hrd=cbr:force-cfr=1:keyint=60:min-keyint=60" \
        -c:a aac -b:a 128k -ar 44100 \
        -f mpegts "udp://127.0.0.1:10000?pkt_size=1316&fifo_size=10000000" > /var/log/nginx/live_listener.log 2>&1
    
    echo "Live Listener finished (stream ended), restarting loop..."
    sleep 1
done &

echo "Starting Nginx..."
nginx -g "daemon off;" || {
    echo "Nginx failed to start! Keeping container alive for debugging..."
    tail -f /dev/null
}
