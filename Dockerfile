FROM ubuntu:24.04

# Install Nginx, Nginx-RTMP module, and FFmpeg
RUN apt update && apt upgrade -y && apt install -y \
    nginx \
    ffmpeg \
    libnginx-mod-rtmp

# Create necessary directories
RUN mkdir -p /run/nginx /var/www/html /assets

# Copy configuration and entrypoint
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

# Expose RTMP port
EXPOSE 1935

ENTRYPOINT ["/entrypoint.sh"]
