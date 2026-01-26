FROM ubuntu:24.04

# Install Nginx, RTMP, FFmpeg, Stunnel and gettext-base (for envsubst)
RUN apt update && apt upgrade -y && apt install -y \
    nginx \
    ffmpeg \
    libnginx-mod-rtmp \
    stunnel4 \
    gettext-base

# Create necessary directories
RUN mkdir -p /run/nginx /var/www/html /assets

# Copy configuration and entrypoint
COPY nginx.conf /etc/nginx/nginx.conf.template
COPY stunnel.conf /etc/stunnel/stunnel.conf

# Use a shell script to start services and substitute environment variables
RUN echo '#!/bin/sh\n\
    envsubst < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf\n\
    stunnel4 /etc/stunnel/stunnel.conf\n\
    echo "Starting Nginx..."\n\
    exec nginx -g "daemon off;"' > /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

# Expose RTMP port
EXPOSE 1935
