FROM eclipse-temurin:25-jre

RUN adduser --disabled-password --gecos '' minecraft

RUN apt-get update && apt-get install -y curl jq

RUN mkdir -p /data /opt/minecraft \
    && chown -R minecraft:minecraft /data /opt/minecraft

VOLUME [ "/data" ]

WORKDIR /data

USER minecraft

COPY --chown=minecraft:minecraft versions.lock.json \
    /opt/minecraft/versions.lock.json

COPY --chmod=755 --chown=minecraft:minecraft docker/entrypoint.sh \
    /usr/local/bin/minecraft-entrypoint

ENTRYPOINT ["minecraft-entrypoint"]

EXPOSE 25565

CMD ["nogui"]
