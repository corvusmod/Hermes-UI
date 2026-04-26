FROM nousresearch/hermes-agent:latest

ARG WEBUI_REPO=https://github.com/nesquena/hermes-webui.git
ARG WEBUI_BRANCH=master

USER root

# Supervisor for running webui + gateway side by side.
# git + gosu are required by the entrypoint (clone/pull webui, drop privileges).
# They live in the base image today, but pinning them here keeps the build
# resilient to base-image changes.
RUN apt-get update && \
    apt-get install -y --no-install-recommends supervisor openssl git gosu && \
    rm -rf /var/lib/apt/lists/*

# ── Hermes Web UI ──
# We do NOT clone or install requirements at build time. Doing it at build
# time has bitten us when uv/base-image versions changed and the deps ended
# up outside the agent venv, leaving `python server.py` unable to import yaml
# and crashing 50ms after spawn with no visible traceback. The entrypoint
# clones (or pulls) into this dir on every start and runs `pip install -r
# requirements.txt` against the activated venv — that path is known-good.
ENV WEBUI_INSTALL=/opt/hermes-webui
RUN mkdir -p ${WEBUI_INSTALL} && chown hermes:hermes ${WEBUI_INSTALL}

# Holographic memory provider: NumPy is optional in upstream but required for
# HRR algebra (probe, reason). Pre-install so the provider is fully functional
# the moment a user runs `hermes memory setup` and selects "holographic".
# The SQLite db lives at $HERMES_HOME/memory_store.db, which is on the
# bind-mounted /opt/data volume, so it persists across redeploys.
RUN . /opt/hermes/.venv/bin/activate && \
    uv pip install --no-cache-dir numpy

# Container marker (webui checks for this)
RUN touch /.within_container

# ── Configuration ──
COPY entrypoint.sh /entrypoint.sh
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod +x /entrypoint.sh

ENV PATH="/opt/hermes/.venv/bin:${PATH}"

# WebUI (8787) + Gateway API (8642)
EXPOSE 8787 8642

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
