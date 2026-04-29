#!/usr/bin/env bash
# wp-splendid: stop the Compose stack and wipe all runtime data.
#
# Preserved : configuration files (db/my.cnf, nginx/*, .env*).
# Wiped     : ./db/* (except my.cnf), ./redis-data/*, ./wordpress/*.
#
# Usage:
#   scripts/cleanup.sh           # interactive (asks for confirmation)
#   scripts/cleanup.sh -y        # non-interactive
#   scripts/cleanup.sh --help    # show help
set -euo pipefail

# cd to the repository root (parent of the directory containing this script).
cd "$(dirname "$(readlink -f "$0")")/.."

if [[ ! -f docker-compose.yml ]]; then
  echo "✗ docker-compose.yml not found in $(pwd)" >&2
  exit 1
fi

force=0
case "${1:-}" in
  -y|--yes)  force=1 ;;
  -h|--help)
    sed -n '2,11p' "$0" | sed 's/^# \?//'
    exit 0
    ;;
  "") ;;
  *)  echo "Unknown argument: $1 (use --help)" >&2; exit 2 ;;
esac

if [[ $force -eq 0 ]]; then
  read -rp "Wipe ./db (except my.cnf), ./redis-data, ./wordpress ? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

echo "→ Stopping the Compose stack…"
if command -v podman-compose >/dev/null 2>&1; then
  podman-compose down --volumes --remove-orphans -t 0 2>/dev/null || true
elif command -v docker >/dev/null 2>&1; then
  docker compose down --volumes --remove-orphans -t 0 2>/dev/null || true
fi

echo "→ Wiping data directories (preserving db/my.cnf)…"

# Files inside bind mounts are owned by UID-mapped users (rootless podman).
# `podman unshare` enters the user namespace so rm/mv operate on them as root.
wipe_cmd='
  cp -p db/my.cnf /tmp/.wp-splendid-mycnf.bak 2>/dev/null || true
  rm -rf db redis-data wordpress
  mkdir -p db redis-data wordpress
  if [ -f /tmp/.wp-splendid-mycnf.bak ]; then
    mv /tmp/.wp-splendid-mycnf.bak db/my.cnf
  fi
'

if command -v podman >/dev/null 2>&1; then
  podman unshare bash -c "$wipe_cmd"
else
  bash -c "$wipe_cmd"
fi

echo "✓ Cleanup done. Restart with: podman-compose up -d"
