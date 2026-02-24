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

# Copy configuration (templates processed by envsubst in entrypoint)
COPY templates/nginx.conf.template /etc/nginx/nginx.conf.template
COPY templates/stunnel.conf.template /etc/stunnel/stunnel.conf.template

# Copy all scripts (including entrypoint)
COPY scripts /scripts

# Make scripts executable and fix line endings (CRLF to LF)
RUN chmod +x /scripts/*.sh && \
    sed -i 's/\r$//' /scripts/*.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]

# Expose RTMP port
EXPOSE 1935
