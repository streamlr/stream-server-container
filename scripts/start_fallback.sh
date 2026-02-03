#!/bin/bash
TARGET_URL="$1"

# TARGET_URL is legacy, we don't need it but we keep variable assignment to avoid breaking anything else just in case, though logically unused.
TARGET_URL="$1"
# if [ -z "$TARGET_URL" ]; then ... REMOVED

# Check if fallback is already running
# Kill any existing feeder process (Live or Fallback)
# Just to be safe we kill by pattern or PID
pkill -f "ffmpeg -i rtmp" || true
pkill -f "ffmpeg -re -stream_loop" || true

echo "$(date): Switching to Fallback Source..." >> /tmp/switch.log

# Feed the pipe with the Fallback Video
# We use copy code (or lightweight transcode) to valid FLV for the pipe
ffmpeg -re -stream_loop -1 -i /assets/fallback.mp4 \
    -vf scale=1920:1080 \
    -c:v libx264 -preset "${FFMPEG_PRESET:-superfast}" -b:v "${FFMPEG_BITRATE:-8000k}" -maxrate "${FFMPEG_BITRATE:-8000k}" -bufsize "${FFMPEG_BUFSIZE:-16000k}" -pix_fmt yuv420p -force_key_frames "expr:gte(t,n_forced*2)" -sc_threshold 0 \
    -c:a aac -b:a 128k -ar 44100 \
    -f mpegts "udp://127.0.0.1:10000?pkt_size=1316" > /tmp/fallback_error.log 2>&1 &
    
echo $! > /tmp/feeder.pid
