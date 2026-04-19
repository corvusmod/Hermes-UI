# Hermes Agent + Web UI — OpenMediaVault

Deploy Hermes Agent with Web UI on OpenMediaVault using the Docker Compose plugin.

## Files

Copy all files from this folder to your OMV compose project directory:

- `Dockerfile` — builds the container image (agent + web UI)
- `docker-compose.yml` — service definition
- `entrypoint.sh` — container startup script
- `supervisord.conf` — process manager config

## Installation

### 1. Copy files to OMV

SSH into your OMV box and copy the files to your compose project directory. For example:

```bash
cd /srv/dev-disk-by-uuid-XXXX/Docker/config/HermesUI
```

Or clone the repo and use the `omv/` folder:

```bash
git clone https://github.com/<your-repo>/hermes-ui.git
cp hermes-ui/omv/* /srv/dev-disk-by-uuid-XXXX/Docker/config/HermesUI/
cd /srv/dev-disk-by-uuid-XXXX/Docker/config/HermesUI/
```

### 2. Create workspaces directory

```bash
mkdir -p ./hermes-workspaces/default
```

### 3. Configure timezone

Edit `docker-compose.yml` and set your timezone:

```yaml
- TZ=Europe/Madrid
```

### 4. Build and start

```bash
docker compose up --build -d
```

The first build takes a few minutes (clones and installs hermes-agent and hermes-webui).

### 5. Run setup

```bash
docker exec -it -u hermes hermes-ui hermes setup
```

This configures your AI provider and API keys.

### 6. Access the Web UI

Open `http://your-omv-ip:8787` in your browser.

## Configuration

### Credentials

API keys and tokens are stored in `./hermes-data/.env`. Edit directly:

```bash
nano ./hermes-data/.env
```

Or run the setup wizard again:

```bash
docker exec -it -u hermes hermes-ui hermes setup
```

### Workspaces

Create subdirectories in `./hermes-workspaces/` for new projects:

```bash
mkdir ./hermes-workspaces/my-project
```

They appear automatically in the Web UI.

### Web UI password

Add to the `environment` section in `docker-compose.yml`:

```yaml
- HERMES_WEBUI_PASSWORD=your-secret-password
```

Then restart: `docker compose restart`

### Profiles

When creating a new profile in the Web UI, enable **"Clone config from default"** so it inherits your provider, model, and API keys.

## Ports

| Port | Service |
|------|---------|
| 8787 | Web UI |
| 8642 | Gateway API |

Ensure these ports are not used by other services. If needed, change them in `docker-compose.yml`:

```yaml
ports:
  - "9090:8787"   # Access Web UI on port 9090 instead
```

## Data

All data is stored in `./hermes-data/` alongside the compose file:

| Path | Content |
|------|---------|
| `./hermes-data/config.yaml` | Agent configuration |
| `./hermes-data/.env` | API keys and tokens |
| `./hermes-data/sessions/` | Chat sessions |
| `./hermes-data/memories/` | Agent memory |
| `./hermes-data/profiles/` | Additional profiles |
| `./hermes-workspaces/` | Project files |

## Important: always use `-u hermes`

OMV runs as root. When executing commands inside the container, **always** use `-u hermes`:

```bash
docker exec -it -u hermes hermes-ui hermes setup
```

Without `-u hermes`, commands run as root and create files that the agent cannot read, causing `PermissionError: [Errno 13] Permission denied` errors (e.g. on `.env`).

If you accidentally ran a command without `-u hermes`, fix permissions with:

```bash
docker exec hermes-ui chown -R hermes:hermes /opt/data
docker compose restart
```

## Useful commands

```bash
# View logs
docker compose logs -f

# Restart
docker compose restart

# Stop
docker compose down

# Reconfigure
docker exec -it -u hermes hermes-ui hermes setup

# Shell access
docker exec -it -u hermes hermes-ui bash

# Fix permissions (if commands were run as root by mistake)
docker exec hermes-ui chown -R hermes:hermes /opt/data
```

## Updating

```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

This pulls the latest hermes-agent and hermes-webui from GitHub. Your data in `./hermes-data/` is preserved.
