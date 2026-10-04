#!/usr/bin/env bash
# One-shot, idempotent Gitea setup for the MyAIBot deploy chain:
#   1. creates the GitHub pull-mirror (if missing)
#   2. creates the Jenkins webhook        (if missing)
#   3. forces an initial mirror sync
#
# `tea` does not implement migrate/webhook endpoints, so this wraps the
# REST API directly. Requires: curl, jq.
#
# Usage:
#   export GITEA_URL="http://gitea:3000"
#   export GITEA_TOKEN="..."                       # token with repo scope
#   export JENKINS_WEBHOOK_URL="http://jenkins:8080/generic-webhook-trigger/invoke?token=..."
#   bash scripts/gitea-setup.sh
#
# Optional overrides: OWNER REPO GITHUB_REPO MIRROR_INTERVAL
#
# Config: copy scripts/gitea.env.example to scripts/gitea.env and fill
# in the values — the script loads it automatically (git-ignored).
# Or export the variables yourself; GITEA_ENV=path/to/file picks a
# different file.
set -euo pipefail

ENV_FILE="${GITEA_ENV:-$(dirname "$0")/gitea.env}"
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
fi

: "${GITEA_URL:?export GITEA_URL (e.g. http://gitea:3000)}"
: "${GITEA_TOKEN:?export GITEA_TOKEN (Gitea token with repo scope)}"
: "${JENKINS_WEBHOOK_URL:?export JENKINS_WEBHOOK_URL (Jenkins invoke URL incl. ?token=)}"

OWNER="${OWNER:-liodali}"
REPO="${REPO:-myaibot}"
GITHUB_REPO="${GITHUB_REPO:-https://github.com/liodali/$REPO.git}"
MIRROR_INTERVAL="${MIRROR_INTERVAL:-8h0m0s}"

api() {
  curl -sS -f -H "Authorization: token $GITEA_TOKEN" \
       -H "Content-Type: application/json" "$@"
}

echo "==> [1/3] pull-mirror $GITHUB_REPO -> $GITEA_URL/$OWNER/$REPO"
if api "$GITEA_URL/api/v1/repos/$OWNER/$REPO" > /dev/null 2>&1; then
  echo "    already exists, skipping"
else
  api -X POST "$GITEA_URL/api/v1/repos/migrate" -d @- > /dev/null <<EOF
{
  "clone_addr": "$GITHUB_REPO",
  "repo_owner": "$OWNER",
  "repo_name": "$REPO",
  "mirror": true,
  "mirror_interval": "$MIRROR_INTERVAL",
  "service": "github",
  "private": true
}
EOF
  echo "    created (interval $MIRROR_INTERVAL)"
fi

echo "==> [2/3] webhook (push-only, main only) -> $JENKINS_WEBHOOK_URL"
if api "$GITEA_URL/api/v1/repos/$OWNER/$REPO/webhooks" \
    | jq -e --arg url "$JENKINS_WEBHOOK_URL" \
        'map(.config.url == $url) | any' > /dev/null 2>&1; then
  echo "    already exists, skipping"
else
  api -X POST "$GITEA_URL/api/v1/repos/$OWNER/$REPO/webhooks" -d @- > /dev/null <<EOF
{
  "type": "gitea",
  "active": true,
  "events": ["push"],
  "branch_filter": "main",
  "config": {
    "url": "$JENKINS_WEBHOOK_URL",
    "content_type": "json",
    "http_method": "POST"
  }
}
EOF
  echo "    created"
fi

echo "==> [3/3] forcing initial mirror sync"
api -X POST "$GITEA_URL/api/v1/repos/$OWNER/$REPO/mirror-sync" > /dev/null
echo "    synced"

echo
echo "Done. Verify in Gitea: $GITEA_URL/$OWNER/$REPO (Settings → Webhooks → Test Delivery)"
