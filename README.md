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
                Single Container
 +-----------------------------------------+
 |  supervisord                             |
 |  +----------------+  +----------------+ |
 |  | Hermes Web UI  |  | Hermes Gateway | |
 |  | (Python)       |  | (Python)       | |
 |  | port 8787      |  | port 8642      | |
 |  +-------+--------+  +--------+-------+ |
 |          |                     |         |
 |     imports agent          CLI/API       |
 |     in-process             messaging     |
 |          |                     |         |
 |     /opt/hermes-agent (shared venv)      |
 |     /opt/data (HERMES_HOME, volume)      |
 +-----------------------------------------+
        |                    |
   host:8787            host:8642
```

- **Web UI** (port 8787): Browser interface for chatting, managing skills, memory, cron jobs, workspaces, and profiles.
- **Gateway** (port 8642): Hermes messaging API for external integrations (Telegram, Discord, etc.).

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

### Web UI password

To protect the Web UI with a password, add to `docker-compose.yml`:

```yaml
environment:
  - HERMES_WEBUI_PASSWORD=your-secret-password
```

Or set it from the Web UI under Settings.

### File permissions (UID/GID)

The install script automatically detects your host UID/GID so files created by the agent are owned by your user. If you need to set them manually, edit `.env.install`:

```
UID=1000
GID=1000
```

On macOS, UIDs typically start at 501.

## Files

### Host files

| File | Purpose |
|------|---------|
| `~/.hermes-data/` | All hermes data. Mounted as `/opt/data` in the container. |
| `~/.hermes-data/.env` | Agent credentials (API keys, tokens). |
| `~/hermes-workspaces/` | Workspaces root. Subdirectories are workspaces. |
| `.env.install` | Docker Compose variables (UID, GID, workspaces path). Auto-generated. |

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

All agent data lives at `~/.hermes-data/` on the host, mounted as `/opt/data` in the container. This persists across container restarts and rebuilds.

To start completely fresh (removes all agent data but keeps workspaces):

```bash
docker compose down
rm -rf ~/.hermes-data
```

## Useful Commands

```bash
# View logs
docker compose logs -f

# Restart
docker compose restart

# Stop
docker compose down

# Reconfigure provider/model
docker exec -it -u hermes hermes-ui hermes setup

# Run hermes CLI commands
docker exec -it -u hermes hermes-ui hermes status
docker exec -it -u hermes hermes-ui hermes model
docker exec -it -u hermes hermes-ui hermes doctor

# Open a shell inside the container
docker exec -it -u hermes hermes-ui bash
```

## Ports

| Port | Service | Description |
|------|---------|-------------|
| 8787 | Web UI | Browser interface |
| 8642 | Gateway API | OpenAI-compatible API for external integrations |

## Troubleshooting

### Web UI shows onboarding wizard after setup

The Web UI and `hermes setup` both configure the agent. If you ran `hermes setup` but the UI still shows the wizard, refresh the page. The configuration is shared — both write to `~/.hermes-data/.env`.

### Permission denied on workspace files

Ensure the UID/GID in `.env.install` match your host user. Run `id -u` and `id -g` on the host and update the values, then restart.

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

## Credits

- [Hermes Agent](https://github.com/nousresearch/hermes-agent) by Nous Research
- [Hermes Web UI](https://github.com/nesquena/hermes-webui) by nesquena
