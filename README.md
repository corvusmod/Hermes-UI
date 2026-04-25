# Hermes Agent + Web UI (Docker)

Single-container Docker deployment of [Hermes Agent](https://github.com/nousresearch/hermes-agent) with [Hermes Web UI](https://github.com/nesquena/hermes-webui).

Both the agent and the web interface run in the same container, sharing the same Python environment. Tools installed by the agent, file access, and configuration all work seamlessly.

## Quick Start

```bash
git clone https://github.com/<your-repo>/hermes-ui.git
cd hermes-ui
./install.sh
```

The install script will:

1. Check that Docker, Docker Compose, and Git are installed
2. Create `~/hermes-workspaces/default/` for your files
3. Create `~/.hermes-data/` for agent data and credentials
4. Build the Docker image
5. Start the container
6. Run `hermes setup` to configure your AI provider and API keys

After installation, open **http://localhost:8787** in your browser.

## Requirements

- Docker with Docker Compose v2
- Git
- ~5 GB of disk space

## Architecture

```
   +-----------------------------------------+      +---------------------+
   |          hermes-ui container            |      |  camofox container  |
   |  supervisord                             |      |  Camoufox (Firefox) |
   |  +----------------+  +----------------+ |      |  + REST API         |
   |  | Hermes Web UI  |  | Hermes Gateway | |      |  port 9377          |
   |  | port 8787      |  | port 8642      | |◄────►|  (network-internal) |
   |  +----------------+  +----------------+ |      +---------------------+
   |  /opt/hermes-agent (shared venv)         |              |
   |  /opt/data (HERMES_HOME, volume)         |              |
   +-----------------------------------------+              |
            |                    |                          |
       host:8787            host:8642               ~/.camofox-data
```

- **Web UI** (port 8787): Browser interface for chatting, managing skills, memory, cron jobs, workspaces, and profiles.
- **Gateway** (port 8642): Hermes messaging API for external integrations (Telegram, Discord, etc.).
- **Camofox sidecar** (port 9377, internal): anti-detection browser the Hermes browser tools route through automatically (`CAMOFOX_URL=http://camofox:9377`). Image: `ghcr.io/corvusmod/camofox-browser:latest`.

## Workspaces

Workspaces are directories the agent can browse and edit. They are mounted from your host machine.

All workspaces live under `~/hermes-workspaces/` on the host, mapped to `/opt/data/workspaces/` inside the container.

### Default workspace

Created automatically at `~/hermes-workspaces/default/`. This is the workspace selected on first launch.

### Adding new workspaces

Create a subdirectory on the host:

```bash
mkdir ~/hermes-workspaces/my-project
```

It appears automatically in the Web UI. Navigate to `/opt/data/workspaces/my-project` to use it.

### Using existing directories

If you have an existing project directory you want the agent to access:

**Symlink** (recommended — changes reflected in both locations):

```bash
ln -s ~/projects/my-app ~/hermes-workspaces/my-app
```

**Copy** (files are independent):

```bash
cp -r ~/projects/my-app ~/hermes-workspaces/my-app
```

## Profiles

Profiles are isolated agent configurations. Each profile has its own config, API keys, memory, sessions, and skills.

### Creating a profile

In the Web UI, go to the Profiles panel and click **Create**. When creating a new profile, enable **"Clone config from default"** so the new profile inherits your provider, model, and API keys. Without this, the new profile starts empty and will not be able to chat until configured.

### Configuring a profile

If you created a profile without cloning the config, you can configure it with:

```bash
docker exec -it -u hermes hermes-ui hermes -p <profile-name> setup
```

Or switch to the profile in the Web UI and use the onboarding wizard.

### Switching profiles

Click on the profile name in the Web UI sidebar to switch between profiles. Each profile maintains its own chat sessions and memory.

## Configuration

### API keys and credentials

All hermes data lives at `~/.hermes-data/` on the host, mounted as `/opt/data` inside the container. Credentials are stored in `~/.hermes-data/.env`.

There are three ways to configure credentials:

1. **`hermes setup`** (recommended for first run): interactive wizard run during installation.
2. **Web UI onboarding**: shown on first launch if no provider is configured.
3. **Edit `~/.hermes-data/.env` directly** from the host:

```bash
nano ~/.hermes-data/.env
```

Add keys in `KEY=VALUE` format, one per line:

```
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
GITHUB_TOKEN=ghp_...
GOOGLE_API_KEY=...
```

All three methods write to the same file. Changes take effect immediately — no container restart needed.

### Holographic memory provider

The `holographic` memory provider (local SQLite + FTS5 + HRR) is **enabled by default for the default profile**. The entrypoint runs `hermes config set memory.provider holographic` on every start, and `numpy` is pre-installed in the agent venv at build time so the algebraic features (`probe`, `reason`, `contradict`) work out of the box.

The fact store lives at `~/.hermes-data/memory_store.db` (i.e. `$HERMES_HOME/memory_store.db` inside the container). It is on the bind-mounted volume, so it survives `docker compose down/up --build` and image rebuilds.

Profiles get their own isolated fact stores. To enable holographic on a non-default profile manually:

```bash
docker exec -it -u hermes hermes-ui hermes -p <name> config set memory.provider holographic
```

### Camofox anti-detection browser

A `camofox` sidecar runs alongside Hermes (`ghcr.io/corvusmod/camofox-browser:latest`). The Hermes browser tools (`browser_navigate`, `browser_snapshot`, `browser_click`, etc.) automatically route through it because the compose file sets `CAMOFOX_URL=http://camofox:9377` on the hermes service.

**Persistence**: cookies and per-Hermes-profile Firefox profiles live at `~/.camofox-data/`, bind-mounted into the camofox container at `/data`. Logins and browsing state survive `docker compose down/up --build` and image bumps.

**Stable user identity**: the entrypoint sets `browser.camofox.managed_persistence: true` on the default profile on every start. For non-default profiles, run it manually:

```bash
docker exec -it -u hermes hermes-ui hermes -p <name> config set browser.camofox.managed_persistence true
```

**Importing cookies** (optional, for sites where you'd rather not log in interactively): export Netscape-format cookie files from your browser, place them at `~/.camofox-data/cookies/<site>.txt`, then ask the agent to import them. To enable, add `CAMOFOX_API_KEY` to the `camofox` service `environment:` block in `docker-compose.yml` (any random hex string) — without it, the cookie-import endpoint returns 403.

**Network**: port 9377 is intentionally not exposed to the host. The camofox API has no auth on its browsing endpoints by default, so we keep it network-internal and only the hermes service can reach it. To debug from the host, uncomment the `ports:` block under the `camofox` service in `docker-compose.yml`.

### Web UI password

To protect the Web UI with a password, add to `docker-compose.yml`:

```yaml
environment:
  - HERMES_WEBUI_PASSWORD=your-secret-password
```

Or set it from the Web UI under Settings.

### File permissions (UID/GID)

The install script automatically detects your host UID/GID and writes them to `docker-compose.yml`. If you need to set them manually, edit the `HERMES_UID` and `HERMES_GID` values in `docker-compose.yml`.

On macOS, UIDs typically start at 501.

## Files

### Host files

| File | Purpose |
|------|---------|
| `~/.hermes-data/` | All hermes data. Mounted as `/opt/data` in the container. |
| `~/.hermes-data/.env` | Agent credentials (API keys, tokens). |
| `~/.hermes-data/memory_store.db` | Holographic memory fact store (default profile). |
| `~/hermes-workspaces/` | Workspaces root. Subdirectories are workspaces. |
| `~/.camofox-data/cookies/` | Camofox cookie imports (Netscape format, optional). |
| `~/.camofox-data/profiles/` | Persistent Firefox profiles per Hermes profile. |

### Container paths

| Path | Description |
|------|-------------|
| `/opt/data/` | HERMES_HOME. Bind-mounted from `~/.hermes-data/`. |
| `/opt/data/.env` | Credentials. Same file as `~/.hermes-data/.env`. |
| `/opt/data/workspaces/` | Workspaces. Bind-mounted from `~/hermes-workspaces/`. |
| `/opt/data/config.yaml` | Agent configuration (model, provider, toolsets). |
| `/opt/hermes-agent/` | Agent source code and Python venv. |
| `/opt/hermes-webui/` | Web UI source code. |

## Data Persistence

| Host path | Survives `docker compose down/up --build` |
|---|---|
| `~/.hermes-data/` | ✓ — config, sessions, skills, holographic DB, profiles |
| `~/hermes-workspaces/` | ✓ — your project files |
| `~/.camofox-data/` | ✓ — browser cookies + per-profile Firefox profiles |

To start completely fresh (removes all agent + browser state, keeps workspaces):

```bash
docker compose down
rm -rf ~/.hermes-data ~/.camofox-data
```

## Useful Commands

`install.sh` drops a `hermes-container` wrapper at `~/.local/bin/hermes-container` that runs the `hermes` CLI inside the running container as the `hermes` user (so file ownership on bind-mounted volumes stays correct). It accepts the same arguments as the `hermes` CLI.

```bash
# View logs
docker compose logs -f

# Restart
docker compose restart

# Stop
docker compose down

# Reconfigure provider/model
hermes-container setup

# Run hermes CLI commands
hermes-container status
hermes-container model
hermes-container doctor

# Per-profile commands
hermes-container -p alice config show
hermes-container -p alice skills install official/security/1password

# Override the container name (default: hermes-ui)
HERMES_CONTAINER=my-hermes hermes-container status

# Open a shell inside the container
docker exec -it -u hermes hermes-ui bash
```

If `~/.local/bin` isn't on your PATH (common on macOS), add it to your shell rc file:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Ports

| Port | Service | Description |
|------|---------|-------------|
| 8787 | Web UI | Browser interface |
| 8642 | Gateway API | OpenAI-compatible API for external integrations |
| 9377 | Camofox | Browser API — **internal only**, not exposed to host |

## Troubleshooting

### Web UI shows onboarding wizard after setup

The Web UI and `hermes setup` both configure the agent. If you ran `hermes setup` but the UI still shows the wizard, refresh the page. The configuration is shared — both write to `~/.hermes-data/.env`.

### Permission denied on workspace files

Ensure `HERMES_UID`/`HERMES_GID` in `docker-compose.yml` match your host user. Run `id -u` and `id -g` on the host, update the values, then restart.

### Profile has no model configured

When creating a new profile, enable **"Clone config from default"**. If you forgot, run:

```bash
docker exec -it -u hermes hermes-ui hermes -p <profile-name> setup
```

### Agent uses wrong working directory

The agent may occasionally use `/opt/hermes-webui` or other internal paths instead of the workspace. This is an LLM instruction-following issue — the Web UI already sends the correct workspace path with every message. An `AGENTS.md` file is created in `~/hermes-workspaces/default/` to reinforce this, but the agent may still ignore it in some cases. If this happens, remind the agent in your message to use the workspace path.

### Container keeps restarting

Check logs for errors:

```bash
docker compose logs --tail 50
```

Common causes: malformed `~/.hermes-data/.env` file, permission issues on the data volume.

## Deploying on OpenMediaVault

For OMV with the compose plugin, use relative paths (`./`) instead of home directory paths (`~/`). The data and workspaces will be stored alongside the compose file.

1. Clone the repo into your OMV compose project directory (or copy the files there)
2. Edit `docker-compose.yml` — change the volume paths:

```yaml
volumes:
  - ./hermes-data:/opt/data
  - ./hermes-workspaces:/opt/data/workspaces
```

3. Create the workspaces directory:

```bash
mkdir -p ./hermes-workspaces/default
```

4. Set `HERMES_UID`/`HERMES_GID` to match your OMV shared folder user:

```bash
# Check your UID/GID
id -u && id -g
```

5. Build and start:

```bash
docker compose up --build -d
```

6. Run setup:

```bash
docker exec -it -u hermes hermes-ui hermes setup
```

Access the Web UI at `http://your-omv-ip:8787`.

Note: if deploying on ARM (e.g. Raspberry Pi), the build will be slow. Consider building on a faster machine and pushing to a registry.

## Credits

- [Hermes Agent](https://github.com/nousresearch/hermes-agent) by Nous Research
- [Hermes Web UI](https://github.com/nesquena/hermes-webui) by nesquena
