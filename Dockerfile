FROM eclipse-temurin:25-jre

WORKDIR /data

COPY --chown=minecraft:minecraft versions.lock.json \
    /opt/minecraft/versions.lock.json

COPY --chown=minecraft:minecraft docker/entrypoint.sh \
    /usr/local/bin/minecraft-entrypoint

USER minecraft

ENTRYPOINT ["minecraft-entrypoint"]

EXPOSE 25565

# Run the Minecraft server
CMD ["nogui"]
