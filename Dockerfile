FROM eclipse-temurin:25-jre

# Load environment variables
ENV MC_VERSION=26.2

# Set up working directory
WORKDIR /app

# Download specified MC-server version using curl
#RUN curl -L -o minecraft_server.jar https://piston-data.mojang.com/v1/objects/

# Minecraft server port
EXPOSE 25565

# Run the Minecraft server
#CMD ["java", "-jar", "minecraft_server.jar"]

