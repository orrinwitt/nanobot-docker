#!/usr/bin/env python3
"""Bake the bundled-version manifest into the image.

Runs at docker build time; output becomes /usr/local/share/bundled-versions.json
and feeds build.yml's release notes (per-build package inventory + deltas).
"""
import json
import subprocess
from datetime import datetime, timezone
from importlib.metadata import version as mdv

PYTHON_PKGS = [
    "aiohttp", "discord.py", "ebooklib", "lightrag-hku", "matrix-nio", "mistune",
    "nh3", "ollama", "opencv-python-headless", "Pillow", "pip-audit",
    "python-socks", "python-telegram-bot", "socksio", "watchdog",
]
SYS_CMDS = {
    "chromium": "chromium --version | head -1",
    "debian-base": "cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2",
    "fabric": "fabric --version | head -1",
    "git": "git --version | head -1",
    "gh": "gh --version | head -1",
    "gws": "gws --version | head -1",
    "nextcloudcmd": "nextcloudcmd --version | head -1",
    "node": "node --version",
    "pinchtab": "PT=$(ls /root/.pinchtab/bin/*/pinchtab-linux-amd64 2>/dev/null | head -1); ${PT} --version 2>/dev/null | head -1 || true",
    "tmux": "tmux -V",
}


def pkg_version(dist):
    try:
        return mdv(dist)
    except Exception:
        return None


def shell_version(cmd):
    try:
        out = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, timeout=30)
        lines = out.stdout.strip().splitlines()
        return lines[0] if lines else None
    except Exception:
        return None


manifest = {
    "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "core": {"nanobot-ai": pkg_version("nanobot-ai")},
    "python_extras": {p: pkg_version(p) for p in PYTHON_PKGS},
    "system": {k: shell_version(c) for k, c in SYS_CMDS.items()},
}
print(json.dumps(manifest, indent=2, sort_keys=True))