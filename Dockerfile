FROM eclipse-temurin:25-jre

# Install dependencies
RUN apt-get update \
    && apt-get install --no-install-recommends -y curl jq netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Create the minecraft user
RUN adduser --disabled-password --gecos '' minecraft

# Create the minecraft data directory, bind volume and set working directory
RUN mkdir -p /data /opt/minecraft && chown -R minecraft:minecraft /data /opt/minecraft
VOLUME [ "/data" ]
WORKDIR /data

COPY --chown=minecraft:minecraft versions.lock.json \
    /opt/minecraft/versions.lock.json

COPY --chmod=755 --chown=minecraft:minecraft docker/entrypoint.sh \
    /usr/local/bin/minecraft-entrypoint

COPY --chmod=755 --chown=minecraft:minecraft docker/healthcheck.sh \
    /usr/local/bin/minecraft-healthcheck

USER minecraft

ENTRYPOINT ["minecraft-entrypoint"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=2m --retries=3 \
    CMD ["/usr/local/bin/minecraft-healthcheck"]

EXPOSE 25565

CMD ["nogui"]
