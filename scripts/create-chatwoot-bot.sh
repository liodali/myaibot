#!/usr/bin/env bash
# Create a Chatwoot Agent Bot and write its credentials to bot.json.
#
# Required env:
#   CHATWOOT_URL  e.g. https://chatwoot.example.com
#   ACCOUNT_ID    e.g. 1
#   USER_TOKEN    admin user access token (Profile → Access Token)
#   BOT_NAME      display name, e.g. "AI Support Bot"
#   OUTGOING_URL  webhook URL of this service, e.g. http://ai-bot:3000/webhook
set -euo pipefail

: "${CHATWOOT_URL:?set CHATWOOT_URL}"
: "${ACCOUNT_ID:?set ACCOUNT_ID}"
: "${USER_TOKEN:?set USER_TOKEN}"
: "${BOT_NAME:=AI Support Bot}"
: "${OUTGOING_URL:?set OUTGOING_URL}"

curl -sS -X POST "${CHATWOOT_URL}/api/v1/accounts/${ACCOUNT_ID}/agent_bots" \
  -H "Content-Type: application/json" \
  -H "api_access_token: ${USER_TOKEN}" \
  -d "{\"name\": \"${BOT_NAME}\", \"description\": \"AI first-line support\", \"outgoing_url\": \"${OUTGOING_URL}\"}" \
  | tee bot.json

echo
echo "bot.json written — copy access_token -> BOT_TOKEN and secret -> BOT_SECRET in .env"
