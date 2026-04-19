FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie AS uv_source
FROM tianon/gosu:1.19-trixie AS gosu_source
FROM debian:13.4

ARG HERMES_REPO=https://github.com/nousresearch/hermes-agent.git
ARG HERMES_BRANCH=main
ARG WEBUI_REPO=https://github.com/nesquena/hermes-webui.git
ARG WEBUI_BRANCH=master

ENV PYTHONUNBUFFERED=1 \
    PLAYWRIGHT_BROWSERS_PATH=/opt/hermes-agent/.playwright \
    HERMES_HOME=/opt/data \
    HERMES_INSTALL=/opt/hermes-agent \
    WEBUI_INSTALL=/opt/hermes-webui

# System dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential nodejs npm python3 ripgrep ffmpeg gcc python3-dev \
        libffi-dev procps git supervisor openssl && \
    rm -rf /var/lib/apt/lists/*

# hermes user: UID 10000, home /opt/data (matches upstream hermes-agent)
RUN useradd -u 10000 -m -d /opt/data hermes

COPY --chmod=0755 --from=gosu_source /gosu /usr/local/bin/
COPY --chmod=0755 --from=uv_source /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/

# ── Hermes Agent ──
RUN git clone --depth 1 --branch ${HERMES_BRANCH} ${HERMES_REPO} ${HERMES_INSTALL}

WORKDIR ${HERMES_INSTALL}

RUN npm install --prefer-offline --no-audit && \
    npx playwright install --with-deps chromium --only-shell 2>/dev/null || true && \
    npm cache clean --force

# Build the agent's built-in web dashboard
RUN cd web && npm install --prefer-offline --no-audit && npm run build || true

# Python venv with agent + webui deps (shared)
RUN chown hermes:hermes ${HERMES_INSTALL}
USER hermes
RUN uv venv && uv pip install --no-cache-dir -e ".[all]"
USER root

# ── Hermes Web UI ──
RUN git clone --depth 1 --branch ${WEBUI_BRANCH} ${WEBUI_REPO} ${WEBUI_INSTALL}

# Install webui's deps into the agent venv
RUN . ${HERMES_INSTALL}/.venv/bin/activate && \
    uv pip install --no-cache-dir -r ${WEBUI_INSTALL}/requirements.txt

# Container marker (webui checks for this)
RUN touch /.within_container

# ── Configuration ──
COPY entrypoint.sh /entrypoint.sh
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod +x /entrypoint.sh

ENV HERMES_WEB_DIST=${HERMES_INSTALL}/hermes_cli/web_dist \
    PATH="${HERMES_INSTALL}/.venv/bin:${PATH}"

# WebUI (8787) + Gateway API (8642)
EXPOSE 8787 8642

VOLUME ["/opt/data"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
