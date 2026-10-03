#!/usr/bin/env bash
# Attach an existing Agent Bot to a Chatwoot inbox.
#
# Required env:
#   CHATWOOT_URL  e.g. https://chatwoot.example.com
#   ACCOUNT_ID    e.g. 1
#   USER_TOKEN    admin user access token
#   INBOX_ID      e.g. 3
#   BOT_ID        agent bot id (from bot.json or the Chatwoot UI)
set -euo pipefail

: "${CHATWOOT_URL:?set CHATWOOT_URL}"
: "${ACCOUNT_ID:?set ACCOUNT_ID}"
: "${USER_TOKEN:?set USER_TOKEN}"
: "${INBOX_ID:?set INBOX_ID}"
: "${BOT_ID:?set BOT_ID (e.g. BOT_ID=$(jq -r .id bot.json))}"

curl -sS -X POST "${CHATWOOT_URL}/api/v1/accounts/${ACCOUNT_ID}/inboxes/${INBOX_ID}/agent_bots" \
  -H "Content-Type: application/json" \
  -H "api_access_token: ${USER_TOKEN}" \
  -d "{\"agent_bot_id\": ${BOT_ID}}"

echo
echo "Bot ${BOT_ID} attached to inbox ${INBOX_ID}"
