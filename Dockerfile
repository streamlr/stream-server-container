FROM ubuntu:24.04

# Install Nginx, Nginx-RTMP module, and FFmpeg
RUN apt update && apt upgrade -y && apt install -y \
    nginx \
    ffmpeg \
    libnginx-mod-rtmp \
    stunnel4

# Create necessary directories
RUN mkdir -p /run/nginx /var/www/html /assets

# Copy configuration and entrypoint
COPY nginx.conf /etc/nginx/nginx.conf
COPY stunnel.conf /etc/stunnel/stunnel.conf

CMD [ "service", "stunnel4", "start", "&&", "service", "nginx", "stop", "&&", "service", "nginx", "start" ]

# Expose RTMP port
EXPOSE 1935
