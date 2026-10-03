# nanobot-docker — Unofficial community Docker image for nanobot
# Upstream: https://github.com/HKUDS/nanobot (MIT)
# Build: docker build -t ghcr.io/orrinwitt/nanobot-docker:latest .
# Push: docker push ghcr.io/orrinwitt/nanobot-docker:latest

# ============================================
# Single-stage build — nanobot installed from PyPI wheel
# (wheel includes prebuilt WebUI, no source build needed)
# ============================================
FROM python:3.12-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    nextcloud-desktop-cmd \
    git \
    curl \
    tmux \
    chromium \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 LTS (replaces Debian's older Node 20)
# Next.js 16 recommends Node 20.9+; Node 22 LTS is current long-term support
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install gws (Google Workspace CLI) via npm
RUN npm install -g @googleworkspace/cli

# Install GitHub CLI (gh)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Fabric (danielmiessler/fabric) - AI augmentation patterns
ARG FABRIC_VERSION=v1.4.507
RUN curl -sL https://github.com/danielmiessler/Fabric/releases/download/${FABRIC_VERSION}/fabric_Linux_x86_64.tar.gz \
    | tar -xz -C /usr/local/bin fabric \
    && chmod +x /usr/local/bin/fabric

# Pre-download all Fabric patterns (baked into image, no boot-time download)
# fabric -U needs .env to exist (dummy key is fine, patterns come from GitHub)
RUN mkdir -p /root/.config/fabric \
    && echo "OPENAI_API_KEY=build-time-dummy" > /root/.config/fabric/.env \
    && fabric -U \
    && echo "Patterns pre-downloaded: $(ls /root/.config/fabric/patterns | wc -l)" \
    && rm /root/.config/fabric/.env

# Install nanobot from PyPI wheel (includes prebuilt WebUI)
# v0.3.0 moved channel deps from pip extras to per-channel manifest.py files;
# we pre-install Matrix, Discord, and Telegram deps explicitly so they're
# baked into the image rather than auto-installed at runtime.
ARG NANOBOT_VERSION=v0.3.5
RUN pip install --no-cache-dir nanobot-ai==${NANOBOT_VERSION#v} \
    && pip install --no-cache-dir \
    "matrix-nio[e2e]>=0.25.2" \
    "aiohttp>=3.9.0,<4.0.0" \
    "mistune>=3.0.0,<4.0.0" \
    "nh3>=0.2.17,<1.0.0" \
    "discord.py>=2.5.2,<3.0.0" \
    "python-telegram-bot[socks,webhooks]>=22.6,<23.0" \
    "socksio>=1.0.0,<2.0.0" \
    "python-socks[asyncio]>=2.8.0,<3.0.0"

# Install additional Python packages
# pip-audit: dependency security scanning
# ebooklib / Pillow / opencv-python-headless: EPUB generation and image processing
# watchdog / lightrag-hku / ollama: vault watching, RAG indexing, Ollama client
RUN pip install --no-cache-dir pip-audit ebooklib Pillow opencv-python-headless watchdog ollama lightrag-hku

# Install PinchTab browser automation
ARG PINCHTAB_VERSION=v0.15.2
RUN mkdir -p /root/.pinchtab/bin/${PINCHTAB_VERSION} \
    && curl -fsSL "https://github.com/pinchtab/pinchtab/releases/download/${PINCHTAB_VERSION}/pinchtab-linux-amd64" \
       -o /root/.pinchtab/bin/${PINCHTAB_VERSION}/pinchtab-linux-amd64 \
    && chmod +x /root/.pinchtab/bin/${PINCHTAB_VERSION}/pinchtab-linux-amd64

# Set working directory
WORKDIR /root/.nanobot

# Environment
ENV PYTHONUNBUFFERED=1
ENV NODE_PATH=/usr/lib/node_modules

# Entrypoint + CMD for default gateway command
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gateway"]
