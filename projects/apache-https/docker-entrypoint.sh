#!/bin/sh
# Generate a throwaway self-signed certificate on first start unless one has
# been mounted at $SSL_DIR. The key is created inside this container only, so
# it never exists in the image, the build context, or the repository.
set -eu

SSL_DIR=/usr/local/apache2/conf/ssl

if [ ! -s "$SSL_DIR/server.key" ] || [ ! -s "$SSL_DIR/server.crt" ]; then
    echo "docker-entrypoint: no certificate in $SSL_DIR, generating a self-signed one for localhost" >&2
    (
        umask 077
        openssl req -x509 -newkey rsa:2048 -sha256 -days 365 -nodes -quiet \
            -subj "/CN=localhost" \
            -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
            -keyout "$SSL_DIR/server.key" \
            -out "$SSL_DIR/server.crt"
    )
    chmod 0644 "$SSL_DIR/server.crt"
fi

exec "$@"
