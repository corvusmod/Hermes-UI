# Hermes Agent + Web UI — OpenMediaVault

Deploy Hermes Agent with Web UI on OpenMediaVault using the Docker Compose plugin.

The stack includes:

- **`hermes`** — the Hermes Agent + Web UI container (built locally from `Dockerfile`)
- **`camofox`** — anti-detection browser sidecar (Camoufox / Firefox with C++ fingerprint spoofing). Pulled from `ghcr.io/corvusmod/camofox-browser:latest`. The Hermes browser tools are auto-routed through it via the `CAMOFOX_URL` env var.

## Files

Copy all files from this folder to your OMV compose project directory:

- `Dockerfile` — builds the Hermes container image (agent + web UI)
- `docker-compose.yml` — services definition (hermes + camofox)
- `entrypoint.sh` — Hermes container startup script
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

### Camofox anti-detection browser

A `camofox` sidecar runs alongside Hermes (`ghcr.io/corvusmod/camofox-browser:latest`). The Hermes browser tools (`browser_navigate`, `browser_snapshot`, `browser_click`, etc.) automatically route through it because the entrypoint sets `CAMOFOX_URL=http://camofox:9377` on the hermes service.

**Persistence**: cookies and per-Hermes-profile Firefox profiles live at `./camofox-data/`, bind-mounted into the camofox container at `/data`. Logins and browsing state survive `docker compose down/up --build` and image bumps.

**Stable user identity**: the entrypoint sets `browser.camofox.managed_persistence: true` in `config.yaml` on every start. Without this, Hermes would send a random `userId` for every browser task and the per-profile data on `./camofox-data/profiles/` would never be reused.

**Importing cookies** (optional, for sites where you'd rather not log in interactively): export Netscape-format cookie files from your browser, place them at `./camofox-data/cookies/<site>.txt`, then ask the agent to import them. To enable this, add `CAMOFOX_API_KEY` to the `camofox` service `environment:` block (any random hex string) — without it, the cookie-import endpoint returns 403.

**Network**: port `9377` is intentionally not exposed to the host. The camofox API has no auth on its browsing endpoints by default, so we keep it network-internal and only the hermes service can reach it. To debug from the host, uncomment the `ports:` block under the `camofox` service in `docker-compose.yml`.

### Holographic memory provider

The `holographic` memory provider (local SQLite + FTS5 + HRR) is **enabled by default**. The entrypoint runs `hermes config set memory.provider holographic` on every start, and `numpy` is pre-installed in the agent venv at build time so the algebraic features (`probe`, `reason`, `contradict`) work out of the box.

The fact store lives at `./hermes-data/memory_store.db` (i.e. `$HERMES_HOME/memory_store.db` inside the container). It is on the bind-mounted volume, so it survives `docker compose down/up --build` and image rebuilds. Nothing extra to back up — keeping `./hermes-data/` is enough.

To switch to a different provider (or disable external memory), use `hermes memory setup` / `hermes memory off`. **Note:** the entrypoint re-asserts `holographic` on every start, so a manual override won't stick across restarts unless you also remove the `hermes config set` line from `entrypoint.sh`.

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
| `./hermes-data/memory_store.db` | Holographic memory fact store |
| `./hermes-workspaces/` | Project files |
| `./camofox-data/cookies/` | Camofox cookie imports (Netscape format, optional) |
| `./camofox-data/profiles/` | Persistent Firefox profiles per Hermes profile (logins survive redeploys) |

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
