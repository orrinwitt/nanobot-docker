# nanobot-docker

> Unofficial community Docker image for [**nanobot**](https://github.com/HKUDS/nanobot) — the lightweight, open-source AI agent for your tools, chats, and workflows.

[![Build Status](../../actions/workflows/build.yml/badge.svg)](../../actions/workflows/build.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## What This Is

This image bundles [nanobot](https://github.com/HKUDS/nanobot) with a set of commonly-needed tools so you can spin up a full-featured AI agent environment with a single `docker pull`. It is **not affiliated with** the nanobot project — all credit for nanobot itself belongs to the [HKUDS team](https://github.com/HKUDS).

### Included Tools

| Component | Purpose |
|-----------|---------|
| [nanobot](https://github.com/HKUDS/nanobot) | AI agent framework (built from source) |
| [Fabric](https://github.com/danielmiessler/fabric) | AI augmentation patterns (257+ pre-downloaded) |
| [gws](https://github.com/googleworkspace/cli) | Google Workspace CLI (Gmail, Calendar, Drive, Docs, Sheets) |
| [GitHub CLI](https://cli.github.com/) | `gh` for issues, PRs, Actions, API access |
| [PinchTab](https://github.com/pinchtab/pinchtab) | Headless browser automation (Chromium-based) |
| [nextcloudcmd](https://github.com/nextcloud/desktop) | Nextcloud sync client for vault synchronization |
| MCP servers | Obsidian + Memory (via `npx`, no global install) |
| tmux | Terminal multiplexer for interactive sessions |
| pip-audit | Python dependency security scanning |
| ebooklib / Pillow | EPUB generation and image processing |
| watchdog / lightrag-hku / ollama | Vault watching, RAG indexing, Ollama client |

## Quick Start

### Pull

```bash
docker pull ghcr.io/orrinwitt/nanobot-docker:latest
```

### Run

```bash
docker run -d \
  --name nanobot \
  -v /path/to/nanobot-data:/root/.nanobot \
  ghcr.io/orrinwitt/nanobot-docker:latest
```

> Only `/root/.nanobot` needs to be mounted. All tools are included in the image.

### Pinned Versions

```bash
# Pull a specific nanobot version
docker pull ghcr.io/orrinwitt/nanobot-docker:v0.2.2

# Pull a verified stable build
docker pull ghcr.io/orrinwitt/nanobot-docker:v0.2.2-stable
```

See [Releases](../../releases) for the full version history and changelogs.

## Version Tags

| Tag | Description |
|-----|-------------|
| `latest` | Most recent build from `main` |
| `v0.2.2` | Pinned to nanobot `v0.2.2` |
| `v0.2.2-stable` | Same as `v0.2.2`, marks a verified stable build |
| `main` | Latest commit on `main` (unstable) |
| `<sha>` | Specific commit hash |

## Volume

Everything persists under `/root/.nanobot`:

| Path | Purpose |
|------|---------|
| `/root/.nanobot/config.json` | nanobot configuration (providers, models, tools) |
| `/root/.nanobot/workspace/` | Workspace (skills, memory, vault) |
| `/root/.nanobot/workspace/secrets/` | Credentials and API keys |
| `/root/.nanobot/workspace/vault/` | Obsidian vault (optional, for MCP Obsidian + Nextcloud sync) |

See the [nanobot documentation](https://nanobot.wiki) for how to configure providers, models, and tools.

## Custom Startup Hook

The entrypoint checks for `workspace/scripts/startup.sh` on the mounted volume and runs it before starting nanobot. This lets you add custom startup logic — starting databases, syncing files, launching sidecar services — without modifying the image.

```bash
# Create your startup script on the volume
cat > /path/to/nanobot-data/workspace/scripts/startup.sh << 'EOF'
#!/bin/sh
# Start a database, sync files, launch services, etc.
pg_ctlcluster 17 main start
nextcloudcmd -u user -p pass /root/.nanobot/workspace/vault https://cloud.example.com
EOF

chmod +x /path/to/nanobot-data/workspace/scripts/startup.sh
```

The script runs with output redirected to `/tmp/startup-hook.log` inside the container. Failures are non-fatal — nanobot will still start even if the script errors.

## Tool Configuration

### MCP Servers

MCP servers run via `npx` (cached automatically, no global install). Add them to your `config.json`:

```json
{
  "mcpServers": {
    "obsidian": {
      "command": "npx",
      "args": ["-y", "@mauricio.wolff/mcp-obsidian", "/root/.nanobot/workspace/vault"],
      "transport": "stdio",
      "disabled": false
    },
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"],
      "transport": "stdio",
      "disabled": false
    }
  }
}
```

### Fabric (AI Augmentation Patterns)

257+ patterns are pre-downloaded at build time (no boot-time download delay). Custom patterns persist in your volume at `workspace/skills/fabric/patterns/` and are copied into the image on boot.

Configure Fabric via `~/.config/fabric/.env` (mount from `secrets/fabric.env`):

```env
OPENAI_API_KEY=your-api-key
OPENAI_API_BASE_URL=https://your-gateway/api/v1
DEFAULT_MODEL=your-model
DEFAULT_VENDOR=OpenAI
FABRIC_DISABLE_RESPONSES_API=true
```

```bash
# List available patterns
fabric --list

# Use a pattern
echo "content" | fabric --pattern summarize
cat file.txt | fabric --pattern extract_wisdom
```

See: https://github.com/danielmiessler/fabric

### Google Workspace (gws)

The `gws` CLI provides access to Google services. Authenticate by placing your OAuth credentials at `workspace/secrets/gws-auth-user.json` — the entrypoint copies them to the right location on boot.

```bash
gws auth login
gws gmail list
gws calendar list
gws drive files list
```

See: https://github.com/googleworkspace/cli

### GitHub CLI (gh)

```bash
gh auth login
gh issue list
gh workflow run build.yml
gh run list --limit 5
```

See: https://cli.github.com/

### PinchTab (Browser Automation)

PinchTab auto-starts on container boot. Token auth is configured via `/root/.pinchtab/config.json` in your volume.

```bash
# Quick test
curl -X POST http://localhost:9867/navigate \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'
```

| Endpoint | Method | Description |
|---------|--------|-------------|
| `/navigate` | POST | Navigate to a URL |
| `/screenshot` | POST | Take a screenshot |
| `/click` | POST | Click an element by ref |
| `/type` | POST | Type text into an element |
| `/scroll` | POST | Scroll the page |
| `/page` | GET | Get page info and element refs |
| `/tabs` | GET | List open tabs |
| `/close` | POST | Close a tab |
| `/health` | GET | Health check |

See: https://github.com/pinchtab/pinchtab

### Nextcloud Sync

The vault can be synced to a Nextcloud instance using `nextcloudcmd`. Place your Nextcloud credentials in `secrets/credentials.json` and add a sync script to `workspace/scripts/`.

See: https://github.com/nextcloud/desktop

## Building from Source

```bash
# Build for a specific nanobot version
docker build --build-arg NANOBOT_VERSION=v0.2.2 -t nanobot-docker .

# Build for latest nanobot release
docker build -t nanobot-docker .
```

## Auto-Updates

This repo includes a daily workflow that checks for new releases of:
- [nanobot](https://github.com/HKUDS/nanobot/releases) (triggers a new versioned release)
- [Fabric](https://github.com/danielmiessler/Fabric/releases) (rebuilds `latest`)
- [PinchTab](https://github.com/pinchtab/pinchtab/releases) (rebuilds `latest`)

When a new nanobot version is detected, the workflow:
1. Updates `NANOBOT_VERSION` in the Dockerfile
2. Commits and pushes to `main` (triggers a new image build)
3. Creates a git tag and GitHub Release with a link to the upstream release notes

Manual trigger: Actions → "Auto-Update from Upstream" → Run workflow.

## License

This Docker image configuration is licensed under the **MIT License**. See [LICENSE](LICENSE).

**nanobot** is licensed under the MIT License by [HKUDS](https://github.com/HKUDS). See [their repository](https://github.com/HKUDS/nanobot) for details.

## Acknowledgments

- **[nanobot](https://github.com/HKUDS/nanobot)** by the HKUDS team — the core agent framework
- **[Fabric](https://github.com/danielmiessler/fabric)** by Daniel Miessler — AI augmentation patterns
- **[PinchTab](https://github.com/pinchtab/pinchtab)** — headless browser automation
- **[gws](https://github.com/googleworkspace/cli)** — Google Workspace CLI