#!/bin/sh

# Substitute environment variables in nginx.conf
envsubst < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Start stunnel
stunnel4 /etc/stunnel/stunnel.conf

# Start the fallback stream initially (idle state)
# We need to construct the URL manually or extract it, but since we have the env var:
if [ ! -z "$KICK_STREAM_KEY" ]; then
    echo "Starting initial fallback stream as www-data..."
    su -s /bin/bash -c "/scripts/start_fallback.sh 'rtmp://127.0.0.1:19350/app/$KICK_STREAM_KEY'" www-data
fi

echo "Starting Nginx..."
exec nginx -g "daemon off;"
