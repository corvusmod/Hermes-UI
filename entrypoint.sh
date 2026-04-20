#!/bin/bash
set -e

HERMES_HOME="${HERMES_HOME:-/opt/data}"
AGENT_DIR="/opt/hermes"

# ── Privilege dropping: remap hermes UID/GID if requested ──
if [ "$(id -u)" = "0" ]; then
    if [ -n "$HERMES_UID" ] && [ "$HERMES_UID" != "$(id -u hermes)" ]; then
        echo "[entrypoint] Changing hermes UID to $HERMES_UID"
        usermod -u "$HERMES_UID" hermes
    fi
    if [ -n "$HERMES_GID" ] && [ "$HERMES_GID" != "$(id -g hermes)" ]; then
        echo "[entrypoint] Changing hermes GID to $HERMES_GID"
        groupmod -o -g "$HERMES_GID" hermes 2>/dev/null || true
    fi

    actual_uid=$(id -u hermes)
    if [ "$(stat -c %u "$HERMES_HOME" 2>/dev/null)" != "$actual_uid" ]; then
        echo "[entrypoint] Fixing ownership of $HERMES_HOME"
        chown -R hermes:hermes "$HERMES_HOME" 2>/dev/null || \
            echo "[entrypoint] Warning: chown failed (rootless?) — continuing"
    fi
fi

# Activate agent venv
source "$AGENT_DIR/.venv/bin/activate"

# ── Bootstrap HERMES_HOME ──
if [ ! -f "$HERMES_HOME/config.yaml" ]; then
    echo "[entrypoint] First run — initializing HERMES_HOME at $HERMES_HOME"
    gosu hermes mkdir -p "$HERMES_HOME"/{cron,sessions,logs,hooks,memories,skills,skins,plans,workspace,home,webui}

    # Only populate .env if empty (it may be bind-mounted from ~/.hermes-env)
    if [ ! -s "$HERMES_HOME/.env" ]; then
        cp "$AGENT_DIR/.env.example" "$HERMES_HOME/.env" 2>/dev/null || true
    fi
    cp "$AGENT_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml" 2>/dev/null || true
    cp "$AGENT_DIR/docker/SOUL.md" "$HERMES_HOME/SOUL.md" 2>/dev/null || true

    # Fallback config
    if [ ! -f "$HERMES_HOME/config.yaml" ]; then
        cat > "$HERMES_HOME/config.yaml" <<'YAML'
schema_version: 19
model:
  provider: anthropic
  model_id: claude-sonnet-4-20250514
gateway:
  timeout: 1800
platform_toolsets:
  cli: [web, terminal, file, memory]
  webhook: [web, terminal, file, memory]
YAML
    fi

    chown -R hermes:hermes "$HERMES_HOME" 2>/dev/null || true
    echo "[entrypoint] Initialization complete"
else
    echo "[entrypoint] Existing HERMES_HOME found at $HERMES_HOME"
fi

# ── Symlink ~/.hermes -> /opt/data ──
# hermes user HOME is /opt/data, so ~/.hermes = /opt/data/.hermes
# webui resolves os.homedir() + '/.hermes' in several places
if [ ! -L "$HERMES_HOME/.hermes" ]; then
    ln -sf "$HERMES_HOME" "$HERMES_HOME/.hermes" 2>/dev/null || true
fi


# ── Symlink agent source into HERMES_HOME ──
# webui discovers agent at HERMES_HOME/hermes-agent
if [ ! -e "$HERMES_HOME/hermes-agent" ]; then
    ln -sf "$AGENT_DIR" "$HERMES_HOME/hermes-agent"
fi

# ── Auto-generate API server key ──
if [ -f "$HERMES_HOME/.api-server-key" ]; then
    export API_SERVER_KEY="${API_SERVER_KEY:-$(cat "$HERMES_HOME/.api-server-key")}"
else
    export API_SERVER_KEY="${API_SERVER_KEY:-$(openssl rand -hex 32)}"
    echo "$API_SERVER_KEY" > "$HERMES_HOME/.api-server-key"
    chmod 600 "$HERMES_HOME/.api-server-key"
    chown hermes:hermes "$HERMES_HOME/.api-server-key" 2>/dev/null || true
fi

# Ensure api_server in config.yaml
if ! grep -q 'api_server' "$HERMES_HOME/config.yaml" 2>/dev/null; then
    echo "[entrypoint] Adding api_server platform to config.yaml"
    cat >> "$HERMES_HOME/config.yaml" <<YAML

platforms:
  api_server:
    enabled: true
    extra:
      port: 8642
      key: ${API_SERVER_KEY}
YAML
    chown hermes:hermes "$HERMES_HOME/config.yaml" 2>/dev/null || true
fi

# ── Symlink hermes to ~/.local/bin ──
mkdir -p "$HERMES_HOME/.local/bin"
ln -sf "$AGENT_DIR/.venv/bin/hermes" "$HERMES_HOME/.local/bin/hermes"
chown -R hermes:hermes "$HERMES_HOME/.local" 2>/dev/null || true

# Sync bundled skills
if [ -d "$AGENT_DIR/skills" ]; then
    gosu hermes python3 "$AGENT_DIR/tools/skills_sync.py" 2>/dev/null || true
fi

# In K8s there's no Docker daemon, so no file is needed.
if [ -z "$KUBERNETES_SERVICE_HOST" ]; then
    echo "docker" > "$HERMES_HOME/.container-mode"
fi

# ── Load hermes .env ──
if [ -f "$HERMES_HOME/.env" ]; then
    set -a
    source "$HERMES_HOME/.env" 2>/dev/null || true
    set +a
fi

# Ensure dirs and fix permissions (covers files modified by docker exec as root)
mkdir -p "$HERMES_HOME/webui" "$HERMES_HOME/workspaces/default" /var/log/supervisor

# Create AGENTS.md in default workspace if missing
if [ ! -f "$HERMES_HOME/workspaces/default/AGENTS.md" ]; then
    cat > "$HERMES_HOME/workspaces/default/AGENTS.md" <<'AGENTS'
# Workspace Instructions

Your working directory is the path shown in the [Workspace: ...] tag.
Always use that path as the root for all file operations.
Never use /opt/hermes, /opt/hermes-webui, or any other internal path as your working directory.
AGENTS
fi
chown -R hermes:hermes "$HERMES_HOME" 2>/dev/null || true
# Ensure .env is readable by hermes even if created by root
chmod 600 "$HERMES_HOME/.env" 2>/dev/null || true

echo "[entrypoint] Starting services..."
exec "$@"
