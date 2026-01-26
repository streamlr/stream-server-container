FROM alpine:latest

# Install Nginx, Nginx-RTMP module, and FFmpeg
RUN apk add --no-cache \
    nginx \
    nginx-mod-rtmp \
    ffmpeg \
    bash

# Create necessary directories
RUN mkdir -p /run/nginx /var/www/html /assets

# Copy configuration and entrypoint
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

# Expose RTMP port
EXPOSE 1935

ENTRYPOINT ["/entrypoint.sh"]
