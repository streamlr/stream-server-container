#!/bin/bash
sleep 5
PID_FILE="/tmp/fallback.pid"
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    echo "Stopping fallback stream (PID $PID)..."
    kill $PID 2>/dev/null
    rm "$PID_FILE"
else
    echo "No callback PID file found. Attempting pkill fallback just in case..."
    pkill -f "ffmpeg -re -stream_loop -1 -i /assets/fallback.mp4"
fi
