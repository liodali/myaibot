#!/bin/sh
# myaibot-deploy — the ONLY thing the Jenkins deploy key can execute.
#
# Forced-command wrapper: authorized_keys pins this script for the
# myaibot-deploy user, so a leaked key cannot open a shell on the host.
#
#   command="/usr/local/bin/myaibot-deploy",no-pty,no-port-forwarding,\
#   no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA... jenkins-deploy
#
# Usage (from Jenkins): ssh myaibot-deploy@localhost "<tag>"
#   <tag>  optional image tag; defaults to :latest
set -eu

# Real endpoints live here, NEVER in the public repo.
# /etc/myaibot/deploy.env (root-readable only):
#   REGISTRY="gitea.yourhost:3000/<owner>/myaibot"
#   DEPLOY_DIR="/opt/myaibot"
if [ -f /etc/myaibot/deploy.env ]; then
    . /etc/myaibot/deploy.env
fi

DEPLOY_DIR="${DEPLOY_DIR:-/opt/myaibot}"
: "${REGISTRY:?set REGISTRY=\"<host[:port]>/<owner>/myaibot\" in /etc/myaibot/deploy.env}"
# forced-command keys pass the client command via SSH_ORIGINAL_COMMAND;
# $1 covers direct invocation; latest is the fallback.
TAG="${1:-${SSH_ORIGINAL_COMMAND:-latest}}"
# reject anything that is not a plausible image tag (defense in depth)
case "$TAG" in
  latest|main-[a-f0-9][a-f0-9]*) ;;
  *) echo "refusing unexpected tag: $TAG" >&2; exit 2 ;;
esac

cd "$DEPLOY_DIR"

# Pin the requested tag in a drop-in override, then pull + recreate.
sed "s|image: .*myaibot:.*|image: ${REGISTRY}:${TAG}|" \
    docker-compose.yml > docker-compose.deploy.yml

podman-compose -f docker-compose.deploy.yml pull bot
podman-compose -f docker-compose.deploy.yml up -d bot

echo "deployed ${REGISTRY}:${TAG}"
