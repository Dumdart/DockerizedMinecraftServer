# Dockerized Minecraft Server

A production-minded Docker image and Compose deployment for an unmodified
Minecraft Java Edition server.

The project builds and publishes its own launcher image to GitHub Container
Registry (GHCR). Mojang's server JAR is not distributed in the image. Each
deployment downloads an explicitly pinned version directly from Mojang,
verifies its published checksum, and stores the verified JAR in private
persistent storage.

## Features

- Custom, non-root Java container image published to GHCR
- Vanilla Minecraft Java Edition without plugins or mods
- Exact Minecraft version and checksum pinning
- Explicit EULA acceptance before download or startup
- Persistent world, configuration, player data, and runtime files
- JVM and container memory configuration through environment variables
- Graceful shutdown with world-save protection
- Container health checks
- Host-side lifecycle and administration commands
- Consistent, save-aware backups
- Multi-architecture image builds
- GitHub Actions tests, security scanning, provenance, and GHCR publication
- Documented Windows-to-Ubuntu migration over Tailscale

## Architecture

```text
Public GitHub repository
  ├─ Dockerfile and launcher scripts
  ├─ Docker Compose deployment
  ├─ pinned Minecraft version metadata
  ├─ management and backup scripts
  └─ GitHub Actions
           │
           ▼
Public GHCR launcher image (no server.jar)
           │
           │ first start with EULA=TRUE
           ▼
Official Mojang download ── checksum verification
           │
           ▼
/opt/apps/minecraft/data on the Ubuntu host
  ├─ server.jar
  ├─ libraries/
  ├─ versions/
  ├─ logs/
  ├─ world/
  ├─ server.properties
  ├─ eula.txt
  ├─ whitelist.json
  └─ ops.json
```

The container uses `/data` as its working directory. Mojang's bundled server
launcher creates `libraries`, `versions`, `logs`, `world`, and its standard
configuration files relative to this directory. Java is supplied by the image
and is not stored in persistent server data.

## Repository structure

```text
.
├─ Dockerfile
├─ compose.yaml
├─ .env.example
├─ versions.lock.json
├─ docker/
│  ├─ ManagementCommand.java
│  ├─ entrypoint.sh
│  ├─ healthcheck.sh
│  └─ manage.sh
├─ scripts/
│  ├─ mc-control.sh
│  ├─ backup.sh
│  ├─ smoke-test.sh
│  ├─ test.sh
│  └─ verify-version-lock.sh
├─ docs/
├─ .github/
│  └─ workflows/
│     └─ ci-image.yml
└─ README.md
```

## Requirements

- Ubuntu host with Docker Engine and Docker Compose v2
- Sufficient storage for the world, generated libraries, logs, and backups
- Outbound HTTPS access to Mojang on the first start of a pinned version
- TCP port `25565` reachable by intended players
- Tailscale or another private administrative path

## Installation

Clone the repository into the homelab application directory:

```bash
sudo mkdir -p /opt/apps
sudo chown "$USER":"$USER" /opt/apps
git clone https://github.com/Dumdart/DockerizedMinecraftServer.git /opt/apps/minecraft
cd /opt/apps/minecraft
```

Create the persistent directories:

```bash
mkdir -p data backups
```

Create the deployment configuration:

```bash
cp .env.example .env
```

Review `.env` and explicitly accept the Minecraft EULA:

```dotenv
EULA=TRUE

JAVA_XMS=2G
JAVA_XMX=4G
CONTAINER_MEMORY=5G

SERVER_PORT=25565
PUID=1000
PGID=1000
TZ=Europe/Oslo
```

Start the server:

```bash
docker compose up -d --wait
docker compose logs -f minecraft
```

The first start downloads the pinned server JAR, validates it, creates the
vanilla directory structure, and starts Minecraft with `nogui`.

Before the server starts, the one-shot `volume_permissions` service aligns the
ownership of `data` and `backups` with `PUID` and `PGID`. This handles migrated
files and deployments that previously ran under a different numeric user. The
preparation service runs with only the capabilities needed to change volume
ownership; the long-running Minecraft and backup processes remain non-root.
The underlying filesystem must support Unix ownership changes.

## Configuration

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `EULA` | Yes | — | Must be exactly `TRUE` before download or startup |
| `MINECRAFT_VERSION` | No | Repository selection | Supplied by Compose; an override must match `versions.lock.json` |
| `MINECRAFT_IMAGE` | No | GHCR `master` tag | Launcher image; pin a release or SHA in production |
| `JAVA_XMS` | No | `2G` | Initial JVM heap |
| `JAVA_XMX` | No | `4G` | Maximum JVM heap |
| `BACKUP_INTERVAL_SECONDS` | No | `1800` | Delay between backup attempts |
| `BACKUP_RETENTION` | No | `48` | Number of recent archives to retain; `0` retains all |
| `CONTAINER_MEMORY` | No | `5G` | Total container memory limit |
| `SERVER_PORT` | No | `25565` | Published Minecraft TCP port |
| `PUID` | No | `1000` | Host user ID used for persistent files |
| `PGID` | No | `1000` | Host group ID used for persistent files |
| `TZ` | No | `UTC` | Container timezone |

Minecraft gameplay settings remain in `data/server.properties`. The container
does not overwrite gameplay properties, whitelist, operator list, ban list, or
world. It manages only `eula.txt` and the private management-server properties
needed for administration and consistent backups.

## Persistent host layout

```text
/opt/apps/minecraft/
├─ compose.yaml
├─ .env
├─ data/
│  ├─ server.jar
│  ├─ libraries/
│  ├─ versions/
│  ├─ logs/
│  ├─ world/
│  ├─ server.properties
│  ├─ eula.txt
│  ├─ whitelist.json
│  ├─ ops.json
│  ├─ banned-players.json
│  ├─ banned-ips.json
│  └─ usercache.json
└─ backups/
```

`data` is the complete live server state. `backups` is deliberately separate
from live data so that replacing or recovering the server directory does not
also remove its recovery points.

## Version and checksum policy

`versions.lock.json` records the repository-selected Minecraft release and maps
it to its official Mojang download URL and checksum. Startup fails closed when:

- the requested version differs from the tracked selection;
- the selected version is absent from the lock file;
- the official download cannot be completed;
- the downloaded JAR does not match the pinned checksum; or
- a cached JAR no longer matches its lock entry.

Minecraft never follows `latest`. Every upgrade, including patch releases,
requires an explicit commit or pull request updating the lock file and Compose
default. Leave `MINECRAFT_VERSION` unset in `.env` so the tracked selection is
authoritative.

After merging an upgrade:

```bash
sh scripts/mc-control.sh backup
git pull --ff-only
docker compose pull
docker compose up -d
docker compose logs -f minecraft
```

Keep the preceding world backup and image tag until the upgraded server has
been validated.

## EULA and server JAR

This project uses Mojang's server software but does not redistribute it.

- The Git repository does not contain `server.jar`.
- GitHub releases do not contain `server.jar`.
- The public GHCR image does not contain `server.jar`.
- The running deployment downloads the selected JAR directly from Mojang.
- The downloaded JAR is cached in the private `/data` bind mount.

The entrypoint requires the operator to set `EULA=TRUE`. Without this explicit
acceptance, it exits before downloading or starting the server.

Operators are responsible for reviewing and complying with the current
[Minecraft EULA](https://www.minecraft.net/en-us/eula) and
[Minecraft Usage Guidelines](https://www.minecraft.net/en-us/usage-guidelines).

## Memory

JVM memory is deployment configuration, not an image build setting:

```dotenv
JAVA_XMS=2G
JAVA_XMX=4G
CONTAINER_MEMORY=5G
```

- `JAVA_XMS` controls the initial heap.
- `JAVA_XMX` controls the maximum heap.
- `CONTAINER_MEMORY` controls the complete container limit.

The container limit must exceed the maximum Java heap to leave room for native
JVM memory, threads, class metadata, networking buffers, and process overhead.
A practical starting margin is at least 1 GiB or 20–25%, whichever is larger.

Memory changes are applied with a controlled restart:

```bash
sh scripts/mc-control.sh restart
```

The JVM maximum heap is a startup-time limit. Automatically selecting a new
ceiling requires a controlled container recreation and is intentionally outside
this project's current scope.

## Operations

The host-side control script keeps routine operations consistent:

```bash
sh scripts/mc-control.sh status
sh scripts/mc-control.sh start
sh scripts/mc-control.sh stop
sh scripts/mc-control.sh restart
sh scripts/mc-control.sh logs
```

`start` and Compose startup can be combined with a readiness check by running
`docker compose up -d --wait`. Readiness verifies the authenticated management
endpoint reports that Minecraft has completed startup. The backup worker also
reports healthy only when its storage and private management connection are
ready.

Live administrative operations use the authenticated Minecraft management
interface:

```bash
sh scripts/mc-control.sh players
sh scripts/mc-control.sh whitelist list
sh scripts/mc-control.sh whitelist add PLAYER_NAME
sh scripts/mc-control.sh whitelist remove PLAYER_NAME
```

Container lifecycle and Minecraft administration are intentionally separate. A
stopped container cannot restart itself, so start and restart actions execute
on the Ubuntu host. Use SSH over Tailscale for remote administration.

The Minecraft management endpoint is bound privately and is not published to
the internet. Its secret is generated per deployment and stored outside Git.
The launcher refreshes only its own management properties on startup; other
Minecraft settings remain under the operator's control.

## Graceful shutdown

The entrypoint runs Java as the managed server process and forwards termination
signals. Compose grants enough stop time for Minecraft to flush chunks and
player state before Docker sends a forced kill.

Use the provided control script or `docker compose stop`; do not kill the Java
process directly:

```bash
sh scripts/mc-control.sh stop
```

## Backups

Create an on-demand save-aware backup with:

```bash
sh scripts/mc-control.sh backup
```

The `backup_worker` Compose service runs `minecraft-backup` every 30 minutes.
It asks Minecraft to disable automatic saving, flushes all state to disk,
copies the persistent state into a frozen staging directory, and immediately
restores automatic saving. It then compresses and verifies the staging copy
while the server continues running. A failed copy restores automatic saving,
and an unverified archive is never published as a completed backup.

Regenerable runtime files (`server.jar`, `libraries`, `versions`, and logs) and
the management secret are excluded so backups focus on worlds and
operator-owned configuration. A restored deployment generates a new secret.

Backups are written to `/opt/apps/minecraft/backups` with UTC timestamps. The
newest 48 archives are retained by default. Set `BACKUP_RETENTION=0` to retain
all archives, or set a different non-negative count as needed. Change
`BACKUP_INTERVAL_SECONDS` to adjust the interval.

The Dockerfile registers the backup command in the shared image. Compose runs
that command in a dedicated sidecar container with read-only access to `/data`
and write access to `/backups`. It uses Mojang's authenticated management
protocol on the private Compose network; the endpoint is not published to the
host.

Always create and verify a backup before:

- upgrading Minecraft;
- changing the launcher image;
- migrating storage;
- restoring older configuration; or
- performing host maintenance that affects Docker storage.

Backups should also be copied to storage outside the VM.

## Migrating an existing Windows server

Do not transfer the outdated replica if a newer world is running elsewhere.
Use the current authoritative server directory from the PC.

1. Deploy and test the container with disposable data.
2. Stop the Windows server using its normal `stop` command.
3. Confirm the Java process has exited.
4. Keep the original directory unchanged as a rollback copy.
5. Transfer mutable state to `/opt/apps/minecraft/data` over Tailscale.
6. Verify file counts and checksums.
7. Correct ownership for the configured `PUID` and `PGID`.
8. Start the container with the same Minecraft version.
9. Validate the overworld, Nether, End, inventories, whitelist, and operators.
10. Back up the validated deployment before changing public connectivity.

Transfer these files:

```text
world/
server.properties
whitelist.json
ops.json
banned-players.json
banned-ips.json
usercache.json
```

Do not transfer:

```text
java-25/
server.jar
libraries/
versions/
logs/
```

The image supplies Java, and the entrypoint recreates executable artifacts from
the pinned official download. Never copy a world while its server is running.

## Development

Build the image locally:

```bash
docker compose build
```

Run the validation suite:

```bash
sh scripts/test.sh
```

Build a disposable image and run the first-start smoke test:

```bash
docker build --tag dockerized-minecraft-server:test .
sh scripts/smoke-test.sh dockerized-minecraft-server:test
```

Exercise the complete disposable Compose stack, backups, readiness, and all
non-interactive runtime controls:

```bash
sh scripts/compose-smoke-test.sh dockerized-minecraft-server:test
```

Generated worlds, downloaded JARs, backups, secrets, and `.env` are excluded
from Git.

## CI/CD and GHCR

GitHub Actions validates pull requests by:

- validating Compose, JSON, shell syntax, and shell scripts;
- testing fail-closed entrypoint validation and a real first start;
- building the image;
- running container smoke tests;
- scanning the final image for known vulnerabilities; and
- verifying version-lock data against Mojang metadata.

Merges and version tags publish immutable images to:

```text
ghcr.io/dumdart/dockerizedminecraftserver
```

Published images include Git tags, the `master` branch tag, and an immutable
commit-SHA tag. Set `MINECRAFT_IMAGE` to a deliberate release or SHA tag in
production so deployments can be reproduced and rolled back.

## Security

- The Minecraft process runs as a non-root user.
- The Java base image and build actions are pinned.
- Only the Minecraft game port is publicly exposed.
- The management endpoint remains private.
- Secrets, worlds, and generated state never enter Git or image layers.
- Every server JAR is checksum-verified before execution.
- Termination signals trigger a graceful server shutdown.
- CI does not publish images from untrusted pull requests.
- Logs do not print management credentials.

## License

The source code in this repository is available under the [MIT License](LICENSE)
and is licensed independently from Minecraft.
Minecraft, its server software, and related assets remain subject to Mojang and
Microsoft's terms. This project is not official, approved by, or affiliated
with Mojang or Microsoft.
