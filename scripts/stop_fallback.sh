# Nginx might pass arguments like "app=live name=key" or just inputs.
# Let's log all args to see what we get
echo "$(date): stop_fallback called with args: $@" >> /tmp/switch.log

# Naive parsing: Assume the first argument is the name, 
# OR if it looks like var=val, try to extract name.
# For now, let's just grab the first arg. If empty, default to "stream"
STREAM_NAME="$1"

# If we get "name=algo", extract it
if [[ "$STREAM_NAME" == name=* ]]; then
  STREAM_NAME="${STREAM_NAME#name=}"
fi

if [ -z "$STREAM_NAME" ]; then
    echo "No stream name provided, defaulting to 'stream'" >> /tmp/switch.log
    STREAM_NAME="stream"
fi

echo "$(date): Switching to Live Source ($STREAM_NAME)..." >> /tmp/switch.log

# Kill the Fallback Feeder (or any other feeder)
pkill -u www-data -f "start_fallback.sh" >> /tmp/switch.log 2>&1 || echo "pkill start_fallback failed" >> /tmp/switch.log
pkill -u www-data -f "ffmpeg -re -stream_loop" >> /tmp/switch.log 2>&1 || echo "pkill fallback ffmpeg failed" >> /tmp/switch.log

echo "Fallback stopped. Live stream should be picked up by the Push Listener automatically." >> /tmp/switch.log
