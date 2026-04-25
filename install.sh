#!/usr/bin/env bash
#
# Hermes Agent + Web UI installer
#
# Usage:
#   ./install.sh
#   ./install.sh --workspace ~/projects
#
set -e

# ── Colors (disabled if not a terminal) ──
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' NC=''
fi

info()  { printf "${CYAN}[info]${NC}  %s\n" "$*"; }
ok()    { printf "${GREEN}[ok]${NC}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[warn]${NC}  %s\n" "$*"; }
err()   { printf "${RED}[error]${NC} %s\n" "$*"; }
fatal() { err "$*"; exit 1; }

# ── Parse arguments ──
while [ $# -gt 0 ]; do
    case "$1" in
        --workspaces|-w)
            HERMES_WORKSPACES="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -w, --workspaces DIR   Root directory for workspaces (default: ~/hermes-workspaces)"
            echo "  -h, --help             Show this help"
            exit 0
            ;;
        *)
            warn "Unknown option: $1"
            shift
            ;;
    esac
done

# ── OS detection ──
OS="$(uname -s)"
case "$OS" in
    Linux*)  PLATFORM="linux" ;;
    Darwin*) PLATFORM="mac" ;;
    *)       PLATFORM="unknown"; warn "Unsupported OS: $OS. Proceeding anyway." ;;
esac

# Script directory = where the Docker files live
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# ── Header ──
echo ""
printf "${BOLD}Hermes Agent + Web UI — Installer${NC}\n"
printf "${BOLD}==================================${NC}\n"
echo ""

# ── Check requirements ──
info "Checking requirements... (platform: $PLATFORM)"

# Docker
if ! command -v docker &>/dev/null; then
    case "$PLATFORM" in
        mac)   fatal "Docker is not installed. Install Docker Desktop from https://docs.docker.com/desktop/install/mac-install/" ;;
        linux) fatal "Docker is not installed. Install it with: curl -fsSL https://get.docker.com | sh" ;;
        *)     fatal "Docker is not installed. Install it from https://docs.docker.com/get-docker/" ;;
    esac
fi
ok "Docker found: $(docker --version | head -1)"

# Docker daemon running
if ! docker info &>/dev/null 2>&1; then
    case "$PLATFORM" in
        mac)   fatal "Docker daemon is not running. Open Docker Desktop and try again." ;;
        linux) fatal "Docker daemon is not running. Start it with: sudo systemctl start docker" ;;
        *)     fatal "Docker daemon is not running. Start it and try again." ;;
    esac
fi
ok "Docker daemon is running"

# Docker Compose (v2 plugin or standalone)
if docker compose version &>/dev/null 2>&1; then
    COMPOSE="docker compose"
    ok "Docker Compose found: $(docker compose version --short 2>/dev/null || echo 'v2')"
elif command -v docker-compose &>/dev/null; then
    COMPOSE="docker-compose"
    ok "Docker Compose found (standalone): $(docker-compose --version | head -1)"
else
    fatal "Docker Compose is not installed. Install it from https://docs.docker.com/compose/install/"
fi

# Git (needed to clone repos during docker build)
if ! command -v git &>/dev/null; then
    case "$PLATFORM" in
        mac)   fatal "Git is not installed. Install Xcode CLI tools: xcode-select --install" ;;
        linux) fatal "Git is not installed. Install it with: sudo apt install git (or your package manager)" ;;
        *)     fatal "Git is not installed." ;;
    esac
fi
ok "Git found: $(git --version)"

# curl (needed for health check)
HAS_CURL=false
if command -v curl &>/dev/null; then
    HAS_CURL=true
else
    warn "curl not found — health check will be skipped"
fi

# Disk space check (need ~5GB for build)
if [ "$PLATFORM" = "mac" ]; then
    available_gb=$(df -g . 2>/dev/null | tail -1 | awk '{print $4}')
else
    available_gb=$(df -BG . 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
fi
if [ -n "$available_gb" ] && [ "$available_gb" -lt 5 ] 2>/dev/null; then
    warn "Less than 5GB of disk space available (${available_gb}GB). Build may fail."
else
    ok "Disk space: ${available_gb:-unknown}GB available"
fi

# Port availability
for port in 8787 8642; do
    in_use=false
    if [ "$PLATFORM" = "mac" ]; then
        lsof -iTCP:"$port" -sTCP:LISTEN &>/dev/null 2>&1 && in_use=true
    else
        ss -tlnp 2>/dev/null | grep -q ":${port} " && in_use=true
    fi
    if [ "$in_use" = true ]; then
        warn "Port ${port} is already in use. The container may fail to start."
    fi
done

# ── Stop existing container if running ──
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^hermes-ui$'; then
    info "Stopping existing hermes-ui container..."
    docker stop hermes-ui &>/dev/null || true
    docker rm hermes-ui &>/dev/null || true
elif docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^hermes-ui$'; then
    docker rm hermes-ui &>/dev/null || true
fi

echo ""

# ── 1) Workspaces ──
printf "${BOLD}Step 1: Workspaces${NC}\n"

# Resolve the suggested default. Precedence:
#   1. --workspaces / -w flag (sets HERMES_WORKSPACES at the top)
#   2. Currently-bound path in docker-compose.yml (so re-runs default to the
#      last choice, even if the file was edited by hand)
#   3. ~/hermes-workspaces
DEFAULT_WS=""
if [ -n "$HERMES_WORKSPACES" ]; then
    DEFAULT_WS="$HERMES_WORKSPACES"
else
    CURRENT_WS=$(grep -oE '[^[:space:]]+:/opt/data/workspaces' "$SCRIPT_DIR/docker-compose.yml" 2>/dev/null \
        | head -1 | sed 's|:/opt/data/workspaces$||')
    if [ -n "$CURRENT_WS" ] && [ "$CURRENT_WS" != "~/hermes-workspaces" ]; then
        DEFAULT_WS="$CURRENT_WS"
    else
        DEFAULT_WS="$HOME/hermes-workspaces"
    fi
fi

# Tilde-expand the default so it shows fully resolved in the prompt
case "$DEFAULT_WS" in
    ~*) DEFAULT_WS="${HOME}${DEFAULT_WS#\~}" ;;
esac

# Prompt every run. In non-interactive shells (CI, piped input), accept the
# default silently — keeps `curl ... | bash` style installs working.
if [ -t 0 ]; then
    printf "  Workspaces root [${BOLD}%s${NC}]: " "$DEFAULT_WS"
    read -r answer
    WORKSPACES_ROOT="${answer:-$DEFAULT_WS}"
else
    info "Non-interactive shell — using default workspace path"
    WORKSPACES_ROOT="$DEFAULT_WS"
fi

# Tilde-expand whatever the user typed
case "$WORKSPACES_ROOT" in
    ~*) WORKSPACES_ROOT="${HOME}${WORKSPACES_ROOT#\~}" ;;
esac

info "All workspaces live here. Create subdirectories for new projects."
mkdir -p "$WORKSPACES_ROOT/default" || fatal "Cannot create workspaces directory"
ok "Workspaces root: $WORKSPACES_ROOT"
ok "Default workspace: $WORKSPACES_ROOT/default"
echo ""

# ── 2) Data directory ──
printf "${BOLD}Step 2: Data directory${NC}\n"

HERMES_DATA="$HOME/.hermes-data"
EXISTING_DATA=false
RUN_SETUP=true

if [ -f "$HERMES_DATA/config.yaml" ]; then
    EXISTING_DATA=true
    warn "Existing hermes data found at $HERMES_DATA"
    info "This contains your config, sessions, memories, and API keys."
    echo ""
    printf "  Do you want to ${BOLD}delete${NC} this data and start fresh? [y/N] "
    read -r answer
    case "$answer" in
        [Yy]*)
            printf "  ${YELLOW}Are you sure?${NC} All hermes data will be permanently lost. Type '${BOLD}yes${NC}' to confirm: "
            read -r confirm
            if [ "$confirm" = "yes" ]; then
                rm -rf "$HERMES_DATA"
                ok "Data removed. Starting fresh."
                EXISTING_DATA=false
            else
                info "Keeping existing data."
            fi
            ;;
        *)
            info "Keeping existing data."
            ;;
    esac
fi

mkdir -p "$HERMES_DATA"

if [ "$EXISTING_DATA" = true ]; then
    ok "Using existing data: $HERMES_DATA"
fi

# Camofox sidecar persistence (cookies + per-Hermes-profile Firefox profiles)
CAMOFOX_DATA="$HOME/.camofox-data"
mkdir -p "$CAMOFOX_DATA"
ok "Camofox data: $CAMOFOX_DATA"
echo ""

# ── 3) Configure docker-compose.yml ──
HOST_UID=$(id -u)
HOST_GID=$(id -g)

if [ "$PLATFORM" = "mac" ] && [ "$HOST_UID" -lt 1000 ]; then
    info "macOS UID ${HOST_UID} detected — this is normal"
fi

# Update UID/GID and workspaces path in docker-compose.yml.
# The workspaces regex is anchored on `:/opt/data/workspaces` so it works on
# both the upstream form (`~/hermes-workspaces:/opt/data/workspaces`) and on
# any previously-substituted absolute path — making re-runs idempotent.
sed -i.bak -E \
    -e "s|HERMES_UID=.*|HERMES_UID=${HOST_UID}|" \
    -e "s|HERMES_GID=.*|HERMES_GID=${HOST_GID}|" \
    -e "s|^([[:space:]]*-[[:space:]]+).+:/opt/data/workspaces$|\1${WORKSPACES_ROOT}:/opt/data/workspaces|" \
    "$SCRIPT_DIR/docker-compose.yml"
rm -f "$SCRIPT_DIR/docker-compose.yml.bak"

ok "Configured docker-compose.yml (UID=${HOST_UID}, GID=${HOST_GID}, workspaces=${WORKSPACES_ROOT})"

# ── 4) Build + Start ──
printf "${BOLD}Step 3: Building and starting${NC}\n"
info "Building Docker image (this may take a few minutes on first run)..."
cd "$SCRIPT_DIR"

if ! $COMPOSE build 2>&1 | tail -5; then
    fatal "Docker build failed. Run '$COMPOSE build' for full output."
fi
ok "Image built"

info "Starting container..."
if ! $COMPOSE up -d 2>&1; then
    fatal "Failed to start container. Run: $COMPOSE logs"
fi

# ── Wait for webui ──
info "Waiting for Web UI to start..."
MAX_WAIT=120
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    if [ "$HAS_CURL" = true ]; then
        if curl -sf http://localhost:8787/health &>/dev/null 2>&1 || \
           curl -sf -o /dev/null -w '%{http_code}' http://localhost:8787/ 2>/dev/null | grep -q "200"; then
            break
        fi
    else
        if docker exec hermes-ui python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8787/')" &>/dev/null 2>&1; then
            break
        fi
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    printf "."
done
echo ""

if [ $ELAPSED -ge $MAX_WAIT ]; then
    warn "Web UI did not respond within ${MAX_WAIT}s."
    warn "It may still be starting. Check: $COMPOSE logs -f"
    exit 1
fi

ok "Web UI is running"
echo ""

# ── 5) Hermes setup ──
printf "${BOLD}Step 4: Hermes setup${NC}\n"

if [ "$EXISTING_DATA" = true ]; then
    info "Existing data detected. Setup may already be configured."
    printf "  Run hermes setup again? [y/N] "
    read -r answer
    case "$answer" in
        [Yy]*) RUN_SETUP=true ;;
        *)     RUN_SETUP=false; info "Skipping setup." ;;
    esac
fi

if [ "$RUN_SETUP" = true ]; then
    info "This will configure your AI provider and API keys."
    info "You can also do this later via the web UI onboarding wizard."
    echo ""
    docker exec -it -u hermes hermes-ui hermes setup || warn "Setup exited (you can re-run it later or use the web UI)"
    # Restart gateway to pick up new config
    docker exec hermes-ui supervisorctl restart hermes-gateway 2>/dev/null || true
fi

# ── 6) Install hermes-container wrapper ──
# Lets the user run hermes CLI commands without typing the full
# `docker exec -it -u hermes hermes-ui hermes ...` prefix every time.
# Always runs as the `hermes` user inside the container so file ownership
# on bind-mounted volumes stays correct.
LOCAL_BIN="$HOME/.local/bin"
WRAPPER="$LOCAL_BIN/hermes-container"
mkdir -p "$LOCAL_BIN"
cat > "$WRAPPER" <<'WRAPPER_EOF'
#!/usr/bin/env bash
# hermes-container — run the hermes CLI inside the running hermes-ui
# container as the `hermes` user.
#
# Usage:
#   hermes-container [args...]              # → hermes [args...]
#   hermes-container -p alice config show   # per-profile commands
#   hermes-container skills install <id>
#
# Override the container name with HERMES_CONTAINER=<name> (default: hermes-ui).
set -e
CONTAINER="${HERMES_CONTAINER:-hermes-ui}"
if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "Error: container '$CONTAINER' is not running." >&2
    echo "Start it with: docker compose up -d (in the hermes-ui project dir)" >&2
    exit 1
fi
# -t requires a TTY on both ends; drop it for piped input/output so scripts
# (e.g. `echo foo | hermes-container chat`) keep working.
DOCKER_FLAGS="-i"
[ -t 0 ] && [ -t 1 ] && DOCKER_FLAGS="-it"
exec docker exec $DOCKER_FLAGS -u hermes "$CONTAINER" hermes "$@"
WRAPPER_EOF
chmod +x "$WRAPPER"
ok "Installed hermes-container wrapper at $WRAPPER"

# Warn if ~/.local/bin isn't on PATH (common on macOS, default on most Linux)
case ":$PATH:" in
    *":$LOCAL_BIN:"*) : ;;
    *)
        warn "$LOCAL_BIN is not on your PATH."
        case "$PLATFORM" in
            mac)   info "Add it to ~/.zshrc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
            *)     info "Add it to ~/.bashrc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
        esac
        ;;
esac

# ── Done ──
echo ""
printf "${BOLD}════════════════════════════════════════${NC}\n"
printf "${GREEN}${BOLD}  Installation complete!${NC}\n"
printf "${BOLD}════════════════════════════════════════${NC}\n"
echo ""
printf "  Web UI:      ${CYAN}http://localhost:8787${NC}\n"
printf "  Gateway:     ${CYAN}http://localhost:8642${NC}\n"
printf "  Workspaces:  ${CYAN}%s${NC}\n" "$WORKSPACES_ROOT"
printf "  Data:        ${CYAN}%s${NC}\n" "$HERMES_DATA"
printf "  Camofox:     ${CYAN}%s${NC}\n" "$CAMOFOX_DATA"
echo ""
printf "  Useful commands:\n"
printf "    ${BOLD}cd %s${NC}\n" "$SCRIPT_DIR"
printf "    ${BOLD}%s logs -f${NC}              # view logs\n" "$COMPOSE"
printf "    ${BOLD}%s restart${NC}              # restart\n" "$COMPOSE"
printf "    ${BOLD}%s down${NC}                 # stop\n" "$COMPOSE"
printf "    ${BOLD}hermes-container setup${NC}                # reconfigure provider/model\n"
printf "    ${BOLD}hermes-container -p alice skills list${NC}  # per-profile commands\n"
echo ""
