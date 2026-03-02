#!/bin/bash
# Fallback feeder: sends fallback video (or black) to UDP 10000 for the Master Streamer.
# Uses FALLBACK_VIDEO; if file missing, generates black + silence via lavfi.
# Runs in a loop so it restarts if FFmpeg exits (e.g. file error).
# Debounce: when called from exec_publish_done, waits FALLBACK_DELAY sec before starting.
# If OBS reconnects during that time, we skip starting (avoids flicker between OBS and fallback).

# Same encoding params as Live Listener (low latency)
GOP="${GOP_SIZE:-15}"
BUF="${BUF_SIZE:-20000k}"
BITRATE="${FFMPEG_BITRATE:-10000k}"
PRESET="${FFMPEG_PRESET:-veryfast}"
FPS="${STREAM_FPS:-60}"
FFMPEG_VIDEO="-vf scale=1920:1080,fps=${FPS} -c:v libx264 -preset ${PRESET} -b:v ${BITRATE} -maxrate ${BITRATE} -bufsize ${BUF} -pix_fmt yuv420p -g ${GOP} -tune zerolatency"
FFMPEG_AUDIO="-c:a aac -b:a 160k -ar 44100"

FALLBACK_FILE="${FALLBACK_VIDEO:-/assets/fallback.mp4}"
# Debounce: segundos de espera antes de iniciar fallback (evita flicker si OBS reconecta rápido)
# Más alto = menos cortes pero más delay al mostrar fallback. Default 0.5s (compromiso).
FALLBACK_DELAY="${FALLBACK_DELAY:-0.5}"

# Debounce: if NOT initial startup and FALLBACK_DELAY > 0, wait before starting fallback
if [[ "$1" != "initial" ]] && [ "${FALLBACK_DELAY}" != "0" ] && [ -n "${FALLBACK_DELAY}" ]; then
    echo "$(date): OBS disconnected. Waiting ${FALLBACK_DELAY}s before fallback (debounce)..." >> /tmp/switch.log
    sleep "$FALLBACK_DELAY"
    # If OBS reconnected during wait, stop_fallback touched /tmp/live_active - don't start fallback
    if [ -f /tmp/live_active ]; then
        MTIME=$(stat -c %Y /tmp/live_active 2>/dev/null || echo 0)
        NOW=$(date +%s)
        if [ $((NOW - MTIME)) -lt "$FALLBACK_DELAY" ]; then
            echo "$(date): OBS reconnected during debounce, skipping fallback" >> /tmp/switch.log
            rm -f /tmp/live_active
            exit 0
        fi
    fi
    rm -f /tmp/live_active
fi

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
        ffmpeg -f lavfi -i "color=c=black:s=1920x1080:r=${FPS}" -f lavfi -i anullsrc=r=44100:cl=stereo \
            -c:v libx264 -preset "${PRESET}" -b:v "${BITRATE}" -maxrate "${BITRATE}" -bufsize "${BUF}" -pix_fmt yuv420p -g "${GOP}" -tune zerolatency \
            $FFMPEG_AUDIO \
            -f mpegts "udp://127.0.0.1:10000?pkt_size=1316" >> /tmp/fallback_error.log 2>&1
    fi
}

# #region agent log
export DEBUG_LOG="${DEBUG_LOG:-/workspace/debug-d2f761.log}"
# #endregion
# Run in background loop so we can be killed by stop_fallback via PID
(
    while true; do
        run_fallback
        # #region agent log
        _err=$(tail -n 1 /tmp/fallback_error.log 2>/dev/null | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g'); _ts=$(date +%s)000; echo "{\"sessionId\":\"d2f761\",\"runId\":\"fallback\",\"hypothesisId\":\"FB_EXIT\",\"location\":\"start_fallback.sh:loop\",\"message\":\"Fallback FFmpeg exited (gap before restart)\",\"data\":{\"fallbackLogLast\":\"$_err\"},\"timestamp\":$_ts}" >> "$DEBUG_LOG" 2>/dev/null || true
        # #endregion
        echo "$(date): Fallback FFmpeg exited, restarting in 2s..." >> /tmp/switch.log
        sleep 2
    done
) &
echo $! > /tmp/feeder.pid
echo "$(date): Fallback feeder started (PID $(cat /tmp/feeder.pid))" >> /tmp/switch.log
# #region agent log
DEBUG_LOG="${DEBUG_LOG:-/workspace/debug-d2f761.log}"; _ts=$(date +%s)000; _pid=$(cat /tmp/feeder.pid 2>/dev/null); echo "{\"sessionId\":\"d2f761\",\"runId\":\"fallback\",\"hypothesisId\":\"D\",\"location\":\"start_fallback.sh\",\"message\":\"Fallback feeder started\",\"data\":{\"feederPid\":\"$_pid\",\"mode\":\"$1\"},\"timestamp\":$_ts}" >> "$DEBUG_LOG" 2>/dev/null || true
# #endregion
