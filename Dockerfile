FROM eclipse-temurin:25-jdk-noble@sha256:3eb81ed94d8c1a34422f19f8188548bdf02cae69c91d0328afdbb7abed90f617 AS tools-build

WORKDIR /build
COPY docker/ManagementCommand.java .
RUN javac --release 25 ManagementCommand.java

FROM eclipse-temurin:25-jre-noble@sha256:2f1da100788559b397bcf48c736169ea5b070bde84e55f203bbee8e83d87a175 AS runtime

ARG IMAGE_REVISION="unknown"
LABEL org.opencontainers.image.title="Dockerized Minecraft Server" \
      org.opencontainers.image.description="Vanilla Minecraft launcher; downloads Mojang's pinned server JAR at runtime" \
      org.opencontainers.image.source="https://github.com/Dumdart/DockerizedMinecraftServer" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        ca-certificates \
        curl \
        jq \
        netcat-openbsd \
        tar \
    && rm -rf /var/lib/apt/lists/* \
    && groupmod --new-name minecraft ubuntu \
    && usermod --login minecraft --home /home/minecraft --move-home \
        --groups minecraft ubuntu \
    && install -d -o minecraft -g minecraft \
        /data /backups /opt/minecraft/tools

COPY --chown=root:root versions.lock.json /opt/minecraft/versions.lock.json
COPY --from=tools-build --chown=root:root \
    /build/ManagementCommand.class \
    /build/ManagementCommand\$ResponseListener.class \
    /opt/minecraft/tools/
COPY --chmod=755 --chown=root:root docker/entrypoint.sh /usr/local/bin/minecraft-entrypoint
COPY --chmod=755 --chown=root:root docker/healthcheck.sh /usr/local/bin/minecraft-healthcheck
COPY --chmod=755 --chown=root:root docker/manage.sh /usr/local/bin/minecraft-manage
COPY --chmod=755 --chown=root:root docker/prepare-volumes.sh /usr/local/bin/minecraft-prepare
COPY --chmod=755 --chown=root:root scripts/backup.sh /usr/local/bin/minecraft-backup

VOLUME ["/data"]
WORKDIR /data
USER minecraft

ENTRYPOINT ["minecraft-entrypoint"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=2m --retries=3 \
    CMD ["/usr/local/bin/minecraft-healthcheck"]

EXPOSE 25565
CMD ["nogui"]
