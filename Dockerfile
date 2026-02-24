FROM ubuntu:24.04

# Install Nginx, RTMP, FFmpeg, Stunnel, gettext-base, and procps (for pkill)
RUN apt update && apt upgrade -y && apt install -y \
    nginx \
    ffmpeg \
    libnginx-mod-rtmp \
    stunnel4 \
    gettext-base \
    procps \
    netcat-openbsd

# Create necessary directories
RUN mkdir -p /run/nginx /var/www/html /assets

# Copy configuration (template is processed by envsubst in entrypoint)
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY stunnel.conf.template /etc/stunnel/stunnel.conf.template

# Copy assets and scripts
# COPY assets /assets
COPY scripts /scripts
COPY entrypoint.sh /entrypoint.sh

# Make scripts executable and fix line endings (CRLF to LF)
RUN chmod +x /entrypoint.sh /scripts/*.sh && \
    sed -i 's/\r$//' /entrypoint.sh /scripts/*.sh

ENTRYPOINT ["/entrypoint.sh"]

# Expose RTMP port
EXPOSE 1935
