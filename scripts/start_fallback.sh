#!/bin/bash
# Fallback feeder: sends fallback video (or black) to UDP 10000 for the Master Streamer.
# Uses FALLBACK_VIDEO; if file missing, generates black + silence via lavfi.
# Runs in a loop so it restarts if FFmpeg exits (e.g. file error).

# Same encoding params as Live Listener (low latency)
GOP="${GOP_SIZE:-30}"
BUF="${BUF_SIZE:-16000k}"
BITRATE="${FFMPEG_BITRATE:-8000k}"
PRESET="${FFMPEG_PRESET:-veryfast}"
FFMPEG_VIDEO="-vf scale=1920:1080 -c:v libx264 -preset ${PRESET} -b:v ${BITRATE} -maxrate ${BITRATE} -bufsize ${BUF} -pix_fmt yuv420p -g ${GOP} -tune zerolatency"
FFMPEG_AUDIO="-c:a aac -b:a 160k -ar 44100"

FALLBACK_FILE="${FALLBACK_VIDEO:-/assets/fallback.mp4}"

# Kill only fallback feeders (do not kill Live Listener: it exits when OBS disconnects)
pkill -f "ffmpeg -re -stream_loop" || true
pkill -f "ffmpeg -f lavfi" || true

echo "$(date): Switching to Fallback Source..." >> /tmp/switch.log

run_fallback() {
    if [ -f "$FALLBACK_FILE" ]; then
        ffmpeg -re -stream_loop -1 -i "$FALLBACK_FILE" \
            $FFMPEG_VIDEO \
            $FFMPEG_AUDIO \
            -f mpegts "udp://127.0.0.1:10000?pkt_size=1316" >> /tmp/fallback_error.log 2>&1
    else
        echo "$(date): $FALLBACK_FILE not found, using black + silence" >> /tmp/switch.log
        ffmpeg -f lavfi -i "color=c=black:s=1920x1080:r=30" -f lavfi -i anullsrc=r=44100:cl=stereo \
            -c:v libx264 -preset "${PRESET}" -b:v "${BITRATE}" -maxrate "${BITRATE}" -bufsize "${BUF}" -pix_fmt yuv420p -g "${GOP}" -tune zerolatency \
            $FFMPEG_AUDIO \
            -f mpegts "udp://127.0.0.1:10000?pkt_size=1316" >> /tmp/fallback_error.log 2>&1
    fi
}

# Run in background loop so we can be killed by stop_fallback via PID
(
    while true; do
        run_fallback
        echo "$(date): Fallback FFmpeg exited, restarting in 2s..." >> /tmp/switch.log
        sleep 2
    done
) &
echo $! > /tmp/feeder.pid
echo "$(date): Fallback feeder started (PID $(cat /tmp/feeder.pid))" >> /tmp/switch.log
