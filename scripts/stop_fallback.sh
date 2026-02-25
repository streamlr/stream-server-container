# Nginx might pass arguments like "app=live name=key" or just inputs.
echo "$(date): stop_fallback called with args: $@" >> /tmp/switch.log

STREAM_NAME="$1"
if [[ "$STREAM_NAME" == name=* ]]; then
  STREAM_NAME="${STREAM_NAME#name=}"
fi
if [ -z "$STREAM_NAME" ]; then
    echo "No stream name provided, defaulting to 'stream'" >> /tmp/switch.log
    STREAM_NAME="stream"
fi

echo "$(date): Switching to Live Source ($STREAM_NAME)..." >> /tmp/switch.log

# Signal that OBS is live (used by start_fallback to debounce brief disconnects)
touch /tmp/live_active

# Prefer killing by PID saved by start_fallback.sh to avoid leaving fallback running
if [ -f /tmp/feeder.pid ]; then
    PID=$(cat /tmp/feeder.pid)
    if kill "$PID" 2>/dev/null; then
        echo "$(date): Killed fallback feeder PID $PID" >> /tmp/switch.log
    else
        kill -9 "$PID" 2>/dev/null || true
    fi
    rm -f /tmp/feeder.pid
fi

# Fallback: kill by pattern in case PID file was missing or process restarted
pkill -u www-data -f "start_fallback.sh" >> /tmp/switch.log 2>&1 || echo "pkill start_fallback failed" >> /tmp/switch.log
pkill -u www-data -f "ffmpeg -re -stream_loop" >> /tmp/switch.log 2>&1 || echo "pkill fallback ffmpeg failed" >> /tmp/switch.log
pkill -u www-data -f "ffmpeg -f lavfi" >> /tmp/switch.log 2>&1 || true

echo "Fallback stopped. Live stream should be picked up by the Push Listener automatically." >> /tmp/switch.log
