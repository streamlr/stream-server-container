#!/bin/bash
TARGET_URL="$1"

if [ -z "$TARGET_URL" ]; then
    echo "Error: No target URL provided."
    exit 1
fi

# Check if fallback is already running
PID_FILE="/tmp/fallback.pid"
if [ -f "$PID_FILE" ]; then
    if kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "Fallback is already running (PID $(cat $PID_FILE))."
        exit 0
    else
        echo "Stale PID file found. removing..."
        rm "$PID_FILE"
    fi
fi

echo "Starting fallback stream to $TARGET_URL"
ffmpeg -re -stream_loop -1 -i /assets/fallback.mp4 \
    -c:v libx264 -preset veryfast -tune zerolatency -maxrate 2500k -bufsize 2500k -pix_fmt yuv420p -g 60 \
    -c:a aac -b:a 128k -ar 44100 \
    -flvflags no_duration_filesize \
    -f flv "$TARGET_URL" > /dev/null 2>&1 &

echo $! > "$PID_FILE"
echo "Fallback started with PID $!"
