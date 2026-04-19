FROM nousresearch/hermes-agent:latest

ARG WEBUI_REPO=https://github.com/nesquena/hermes-webui.git
ARG WEBUI_BRANCH=master

USER root

# Supervisor for running webui + gateway side by side
RUN apt-get update && \
    apt-get install -y --no-install-recommends supervisor openssl && \
    rm -rf /var/lib/apt/lists/*

# ── Hermes Web UI ──
ENV WEBUI_INSTALL=/opt/hermes-webui
RUN git clone --depth 1 --branch ${WEBUI_BRANCH} ${WEBUI_REPO} ${WEBUI_INSTALL}

# Install webui's deps into the agent venv
RUN . /opt/hermes/.venv/bin/activate && \
    uv pip install --no-cache-dir -r ${WEBUI_INSTALL}/requirements.txt

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
