#!/usr/bin/env bash
# First-time push to GitHub (run in Git Bash from project root)
#
# Usage:
#   ./scripts/first-push.sh YOUR_GITHUB_USERNAME
#
# Example:
#   ./scripts/first-push.sh miroglu

set -euo pipefail

USER="${1:-}"
if [ -z "${USER}" ]; then
  echo "Usage: $0 GITHUB_USERNAME"
  echo "Example: $0 miroglu"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

REMOTE="https://github.com/${USER}/BadSector.git"

if [ -f .env ]; then
  echo "OK: .env exists locally and is gitignored (will NOT be pushed)."
else
  echo "Tip: copy .env.example to .env for local secrets after push."
fi

if [ ! -d .git ]; then
  git init
  git branch -M main
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "${REMOTE}"
else
  git remote set-url origin "${REMOTE}"
fi

git add .
git status

echo ""
echo "Committing..."
git commit -m "Initial commit: BadSector edge security platform" || true

echo ""
echo "Pushing to ${REMOTE} ..."
git push -u origin main

echo ""
echo "Done. Server install:"
echo "  sudo git clone ${REMOTE} /opt/badsector"
