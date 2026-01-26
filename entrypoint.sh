#!/bin/bash

# Start Nginx in the background
nginx

echo "Nginx started. Ingest is ready at rtmp://localhost:1935/ingest/stream"

# Environment variables (to be provided via docker-compose or .env)
# KICK_STREAM_URL: The RTMPS URL from Kick
# KICK_STREAM_KEY: Your stream key
# FALLBACK_VIDEO: Path to fallback video (default /assets/fallback.mp4)

FALLBACK_VIDEO=${FALLBACK_VIDEO:-"/assets/fallback.mp4"}

if [ ! -f "$FALLBACK_VIDEO" ]; then
    echo "Warning: Fallback video $FALLBACK_VIDEO not found. Creating a placeholder..."
    mkdir -p /assets
    ffmpeg -f lavfi -i color=c=black:s=1920x1080:r=30 -f lavfi -i anullsrc=r=44100:cl=stereo -t 10 -pix_fmt yuv420p "$FALLBACK_VIDEO"
fi

# The FFmpeg command:
# 1. Inputs: Fallback video (looped) + RTMP Ingest (local)
# 2. Logic: Always send fallback video as background. Overlay live stream if available.
# 3. Output: Kick RTMPS

# Note: We use -re for the fallback to maintain real-time speed.
# The ingest stream is already real-time.

echo "Starting FFmpeg bridge to Kick..."

ffmpeg -re -stream_loop -1 -i "$FALLBACK_VIDEO" \
       -f rtmp -i "rtmp://localhost:1935/ingest/stream" \
       -filter_complex "[0:v][1:v]overlay=shortest=0:eof_action=pass[v];[0:a][1:a]amix=inputs=2:duration=first[a]" \
       -map "[v]" -map "[a]" \
       -c:v libx264 -preset veryfast -b:v 4000k -maxrate 4000k -bufsize 8000k \
       -pix_fmt yuv420p -g 60 -c:a aac -b:a 128k -ar 44100 \
       -f flv "$KICK_STREAM_URL/$KICK_STREAM_KEY"
