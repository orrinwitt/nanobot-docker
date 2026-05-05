# Nanobot Custom Image
# Build: docker build -t ghcr.io/orrinwitt/nanobot-custom:latest .
# Push: docker push ghcr.io/orrinwitt/nanobot-custom:latest

# ============================================
# Stage 1: Build nanobot from source
# ============================================
FROM python:3.12-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git \
    gcc \
    g++ \
    make \
    && rm -rf /var/lib/apt/lists/*

# Clone nanobot repository (specific version)
ARG NANOBOT_VERSION=v0.1.5.post3
WORKDIR /build
RUN git clone --depth 1 --branch ${NANOBOT_VERSION} https://github.com/HKUDS/nanobot.git .

# Install nanobot and dependencies (regular install, not editable)
RUN pip install --no-cache-dir .

# ============================================
# Stage 2: Runtime image
# ============================================
FROM python:3.12-slim

# Install runtime dependencies (standard locations)
RUN apt-get update && apt-get install -y \
    nodejs \
    npm \
    nextcloud-desktop-cmd \
    git \
    curl \
    tmux \
    chromium \
    && rm -rf /var/lib/apt/lists/*

# MCP servers will be run via npx (no global install needed)
# npx caches packages in ~/.npm/_npx

# Install gws (Google Workspace CLI) via npm
RUN npm install -g @googleworkspace/cli

# Install GitHub CLI (gh)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Fabric (danielmiessler/fabric) - AI augmentation patterns
ARG FABRIC_VERSION=v1.4.452
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

# Install pip-audit for dependency security scanning
# Install ebooklib for EPUB generation
# Install Pillow for image/covers
# Install opencv-python-headless for image processing
RUN pip install --no-cache-dir pip-audit ebooklib Pillow opencv-python-headless watchdog ollama lightrag-hku

# Install PinchTab browser automation (v0.8.6)
ARG PINCHTAB_VERSION=v0.10.0
RUN mkdir -p /root/.pinchtab/bin/${PINCHTAB_VERSION} \
    && curl -fsSL "https://github.com/pinchtab/pinchtab/releases/download/${PINCHTAB_VERSION}/pinchtab-linux-amd64" \
       -o /root/.pinchtab/bin/${PINCHTAB_VERSION}/pinchtab-linux-amd64 \
    && chmod +x /root/.pinchtab/bin/${PINCHTAB_VERSION}/pinchtab-linux-amd64

# Copy nanobot from builder
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Set working directory
WORKDIR /root/.nanobot

# Environment
ENV PYTHONUNBUFFERED=1
ENV NODE_PATH=/usr/lib/node_modules

# Match original image: ENTRYPOINT + CMD for default gateway command
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["gateway"]