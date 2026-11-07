FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Web servers, lecbh runtime prerequisites, and test tooling (jq).
# python3-venv/libaugeas0 let the pip installer path run without extra apt work.
RUN apt-get update && apt-get install -y --no-install-recommends \
        apache2 \
        nginx \
        netcat-openbsd \
        jq \
        procps \
        ca-certificates \
        python3-venv \
        libaugeas0 && \
    rm -rf /var/lib/apt/lists/*

# Apache owns port 80; move Nginx to 8080 so both can run side by side.
# The IPv6 listener is dropped because Docker networks often have IPv6 disabled.
RUN sed -i \
        -e 's/listen 80 default_server;/listen 8080 default_server;/' \
        -e '/listen \[::\]:80 default_server;/d' \
        /etc/nginx/sites-available/default

WORKDIR /app
COPY lecbh.sh /app/lecbh.sh

HEALTHCHECK --interval=2s --timeout=3s --retries=15 \
    CMD nc -z localhost 80 && nc -z localhost 8080

CMD ["bash", "-c", "service apache2 start && service nginx start && exec sleep infinity"]
