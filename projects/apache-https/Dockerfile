# Reproducible rebuild of my Dockerized Apache HTTPS exercise. See README.md.
#
# Pinned to the same Apache release and base image layers as the original
# hailmogambo9/contapache:2.0 image (httpd 2.4.69 on Debian trixie). The digest
# is the multi-arch index for httpd:2.4.69 as listed on Docker Hub on 2026-10-29.
FROM httpd:2.4.69@sha256:d3accb516506c05ae0068bb54ba6798a10b249b64db91268fca692326cb02b4b

LABEL org.opencontainers.image.title="apache-https" \
      org.opencontainers.image.description="Apache httpd serving a static page over HTTP and HTTPS, running as a non-root user" \
      org.opencontainers.image.source="https://github.com/AdityaBhardwaj04/homelab"

# Explicit configuration files replace the stock config, instead of editing
# files inside a running container and capturing them with `docker commit`.
COPY conf/httpd.conf /usr/local/apache2/conf/httpd.conf
COPY conf/extra/httpd-ssl.conf /usr/local/apache2/conf/extra/httpd-ssl.conf
COPY htdocs/ /usr/local/apache2/htdocs/
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# The runtime user only needs to write the PID file, the TLS session cache,
# and its own certificate. Configuration and content stay root-owned.
# No certificate or key is created at build time, so none ends up in a layer.
RUN mkdir -p /usr/local/apache2/conf/ssl \
 && chown www-data:www-data /usr/local/apache2/logs /usr/local/apache2/conf/ssl

USER www-data

# Unprivileged ports, so Apache never needs root to bind.
EXPOSE 8080 8443

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["httpd-foreground"]
