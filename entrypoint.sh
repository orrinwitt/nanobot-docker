#!/bin/sh
# Nanobot entrypoint — configures tools before starting

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

# ── Vault Watchdog (Nextcloud sync) ─────────────────────────────────────────
WATCHDOG_SCRIPT="/root/.nanobot/workspace/scripts/vault-watchdog.py"
if [ -f "$WATCHDOG_SCRIPT" ]; then
    python3 "$WATCHDOG_SCRIPT" > /dev/null 2>&1 &
fi

# ── PinchTab Browser Automation ─────────────────────────────────────────────
# PinchTab requires PINCHTAB_CHROME_NO_SANDBOX=1 in container/non-root environments
export PINCHTAB_CHROME_NO_SANDBOX=1
PINCHTAB_SERVICE="/root/.nanobot/workspace/scripts/pinchtab-service.sh"
if [ -f "$PINCHTAB_SERVICE" ]; then
    "$PINCHTAB_SERVICE" start > /dev/null 2>&1 &
fi

# ── James Blinds Platform (dev environment) ──────────────────────────────────
JBP_DIR="/root/.nanobot/workspace/james-blinds-platform"
JBP_DATA="$JBP_DIR/postgres-data"

if [ -d "$JBP_DIR" ] && [ -d "$JBP_DATA" ]; then
    # Ensure PostgreSQL cluster config exists
    if ! pg_lsclusters 2>/dev/null | grep -q "17 main"; then
        pg_createcluster 17 main > /dev/null 2>&1 || true
    fi

    # ALWAYS repoint the cluster at the persistent data directory on the volume.
    # pg_createcluster --datadir only works at creation time; after a restart
    # the config defaults to /var/lib/postgresql/17/main (ephemeral, empty).
    sed -i "s|^data_directory = .*|data_directory = '$JBP_DATA'|" /etc/postgresql/17/main/postgresql.conf 2>/dev/null || true

    # Ensure the postgres user can traverse to the persistent volume path
    chmod o+x /root /root/.nanobot /root/.nanobot/workspace /root/.nanobot/workspace/james-blinds-platform 2>/dev/null || true
    chown -R postgres:postgres "$JBP_DATA" 2>/dev/null || true
    chmod 700 "$JBP_DATA" 2>/dev/null || true

    # Fix pg_hba.conf: use trust for local connections (container-internal only)
    cat > /etc/postgresql/17/main/pg_hba.conf << 'HBACONF'
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
HBACONF

    # Start PostgreSQL if not already running
    if ! pg_isready -q 2>/dev/null; then
        pg_ctlcluster 17 main start > /dev/null 2>&1 || true

        # Wait for PostgreSQL to be ready
        for i in $(seq 1 30); do
            pg_isready -q 2>/dev/null && break
            sleep 1
        done
    fi

    # Run migrations + seed + fix indexes/columns (idempotent, skips if already done)
    PGPASSWORD=jbplatform psql -h localhost -U jbplatform -d jbplatform -c "SELECT 1" > /dev/null 2>&1 && {
        cd "$JBP_DIR"
        npx prisma migrate deploy > /dev/null 2>&1 || true
        PGPASSWORD=jbplatform psql -h localhost -U jbplatform -d jbplatform -c "
            CREATE UNIQUE INDEX IF NOT EXISTS \"Project_name_state_key\" ON \"Project\" (name, state);
            CREATE UNIQUE INDEX IF NOT EXISTS \"GC_name_key\" ON \"GC\" (name);
            CREATE UNIQUE INDEX IF NOT EXISTS \"Manufacturer_name_key\" ON \"Manufacturer\" (name);
            CREATE UNIQUE INDEX IF NOT EXISTS \"BidRecipient_bidId_gcId_key\" ON \"BidRecipient\" (\"bidId\", \"gcId\");
        " > /dev/null 2>&1 || true
        PGPASSWORD=jbplatform psql -h localhost -U jbplatform -d jbplatform -c "
            ALTER TABLE \"Bid\" ALTER COLUMN \"estimatorId\" DROP NOT NULL;
            ALTER TABLE \"Bid\" ALTER COLUMN \"bidDate\" DROP NOT NULL;
            ALTER TABLE \"Bid\" ALTER COLUMN \"gcId\" DROP NOT NULL;
            ALTER TABLE \"Bid\" ALTER COLUMN \"won\" DROP NOT NULL;
            ALTER TABLE \"Bid\" ALTER COLUMN \"veSubmitted\" DROP NOT NULL;
        " > /dev/null 2>&1 || true
        PGPASSWORD=jbplatform psql -h localhost -U jbplatform -d jbplatform -c "
            CREATE TABLE IF NOT EXISTS \"SyncLog\" (
                id SERIAL PRIMARY KEY,
                sheet_name TEXT NOT NULL,
                last_sync TIMESTAMP,
                row_count INTEGER,
                status TEXT,
                error TEXT
            );
        " > /dev/null 2>&1 || true
        # Seed (idempotent — uses findFirst+create, skips if data exists)
        DATABASE_URL="postgresql://jbplatform:jbplatform@localhost:5432/jbplatform?schema=public" \
            npx tsx prisma/seed.ts > /dev/null 2>&1 || true
    }

    # Auto-sync from Google Drive (fresh data on every restart)
    # Downloads the current invite-tracker spreadsheet, then runs sync + dedup in background
    if command -v gws >/dev/null 2>&1 && [ -f "$JBP_DIR/scripts/sync-pg.js" ]; then
        (
            cd /tmp \
            && gws drive files export --params '{"fileId":"1icex17JWdlsDEf8VTW3KtGK1jLmhu4lj4XkU8H26iwg","mimeType":"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}' -o invite-tracker.xlsx > /dev/null 2>&1 \
            && cp /tmp/invite-tracker.xlsx "$JBP_DIR/data/invite-tracker.xlsx" \
            && cd "$JBP_DIR" \
            && node scripts/sync-pg.js > /tmp/jbp-sync.log 2>&1 \
            && python3 scripts/deduplicate.py >> /tmp/jbp-sync.log 2>&1
        ) || echo "[JBP] Auto-sync failed — see /tmp/jbp-sync.log" >&2 &
    fi

    # Start Next.js dev server on port 8501
    if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:8501/ | grep -q "200"; then
        cd "$JBP_DIR"
        nohup bash -c "PORT=8501 npm run dev" > /tmp/jbp-dev.log 2>&1 &
        echo $! > /tmp/jbp.pid
    fi
fi

exec python -m nanobot "$@"
