#!/bin/sh
# nanobot-docker entrypoint — configures tools before starting
#
# This entrypoint sets up tool configurations from the mounted volume
# and then execs into nanobot (the default gateway command).

SECRETS="/root/.nanobot/workspace/secrets"

# ── gws (Google Workspace CLI) ──────────────────────────────────────────────
GWS_CREDS_SRC="$SECRETS/gws-auth-user.json"
if [ -f "$GWS_CREDS_SRC" ]; then
    mkdir -p /root/.config/gws
    cp "$GWS_CREDS_SRC" /root/.config/gws/credentials.json
    export GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=/root/.config/gws/credentials.json
fi

# ── Fabric (AI augmentation patterns) ───────────────────────────────────────
FABRIC_ENV_SRC="$SECRETS/fabric.env"
FABRIC_PATTERNS_SRC="/root/.nanobot/workspace/skills/fabric/patterns"
FABRIC_PATTERNS_DEST="/root/.config/fabric/patterns"

mkdir -p /root/.config/fabric

# Copy API key
if [ -f "$FABRIC_ENV_SRC" ]; then
    cp "$FABRIC_ENV_SRC" /root/.config/fabric/.env
fi

# Copy custom patterns from persistence volume (if they exist)
# Standard patterns are baked into the image
if [ -d "$FABRIC_PATTERNS_SRC" ]; then
    for pattern_dir in "$FABRIC_PATTERNS_SRC"/*; do
        if [ -d "$pattern_dir" ]; then
            pattern_name=$(basename "$pattern_dir")
            mkdir -p "$FABRIC_PATTERNS_DEST/$pattern_name"
            cp -r "$pattern_dir"/* "$FABRIC_PATTERNS_DEST/$pattern_name/" 2>/dev/null || true
        fi
    done
fi

# Check for pattern updates from GitHub (quick if already current)
# Runs in background to not block startup, logs to /tmp/fabric-update.log
if [ -f "/root/.config/fabric/.env" ]; then
    (fabric -U > /tmp/fabric-update.log 2>&1 &) || true
fi

# ── PinchTab Browser Automation ─────────────────────────────────────────────
# PinchTab requires PINCHTAB_CHROME_NO_SANDBOX=1 in container/non-root environments
export PINCHTAB_CHROME_NO_SANDBOX=1
PINCHTAB_SERVICE="/root/.nanobot/workspace/scripts/pinchtab-service.sh"
if [ -f "$PINCHTAB_SERVICE" ]; then
    "$PINCHTAB_SERVICE" start > /dev/null 2>&1 &
fi

# ── User startup hooks ───────────────────────────────────────────────────────
# If workspace/scripts/startup.sh exists, run it before nanobot starts.
# This lets users add their own startup logic (e.g., starting custom services)
# without modifying the image.
USER_STARTUP="/root/.nanobot/workspace/scripts/startup.sh"
if [ -f "$USER_STARTUP" ]; then
    chmod +x "$USER_STARTUP" 2>/dev/null || true
    "$USER_STARTUP" > /tmp/startup-hook.log 2>&1 || true
fi

exec python -m nanobot "$@"