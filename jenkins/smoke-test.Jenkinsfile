// Smoke test for the deployed MyAIBot container — run any time.
//   1. health probe  : curl sidecar -> http://ai-bot:3000/health
//   2. signed webhook: python sidecar posts an HMAC-valid message_created
//                      (BOT_SECRET read from the runtime .env on the host)
//   3. log tail      : last lines from the bot
// Uses the agent's podman socket; images fully qualified (RHEL podman).

pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 5, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    parameters {
        string(name: 'ACCOUNT_ID', defaultValue: '1', description: 'Chatwoot account id for the fake event')
        string(name: 'CONVERSATION_ID', defaultValue: '999999', description: 'Fake conversation id (does not exist — handler will log a fetch failure, that is OK)')
    }

    stages {
        stage('Health probe') {
            steps {
                sh '''
                  set -e
                  export CONTAINER_HOST="unix:///run/podman/podman.sock"
                  echo "--- GET http://ai-bot:3000/health :"
                  podman run --rm --network chatwoot_internal \
                    docker.io/curlimages/curl:latest -s -w "\\nHTTP %{http_code}\\n" \
                    http://ai-bot:3000/health
                '''
            }
        }

        stage('Signed webhook simulation') {
            steps {
                sh '''
                  set -e
                  export CONTAINER_HOST="unix:///run/podman/podman.sock"
                  cat > smoke_webhook.py <<'PYEOF'
import hmac, hashlib, json, time, urllib.request

env = {}
for line in open('/runtime/.env'):
    line = line.strip()
    if '=' in line and not line.startswith('#'):
        k, v = line.split('=', 1)
        env[k.strip()] = v.strip().strip('"').strip("'")

secret = env.get('BOT_SECRET', '')
body_d = {
    'event': 'message_created',
    'id': int(time.time() * 1000),
    'content': 'smoke test ping',
    'message_type': 'incoming',
    'account': {'id': int(env.get('SMOKE_ACCOUNT', '1'))},
    'conversation': {'id': int(env.get('SMOKE_CONV', '999999')), 'status': 'pending'},
}
body = json.dumps(body_d).encode()
ts = str(int(time.time()))
sig = 'sha256=' + hmac.new(secret.encode(), (ts + '.' + body.decode()).encode(),
                           hashlib.sha256).hexdigest()
req = urllib.request.Request('http://ai-bot:3000/webhook', data=body, headers={
    'Content-Type': 'application/json',
    'X-Chatwoot-Timestamp': ts,
    'X-Chatwoot-Signature': sig,
})
try:
    print('HTTP', req.get_full_url(), '->', urllib.request.urlopen(req, timeout=10).read().decode())
except urllib.error.HTTPError as e:
    print('HTTP', e.code, e.read().decode())
    raise SystemExit(1)
PYEOF
                  echo "--- POST http://ai-bot:3000/webhook (HMAC-signed) :"
                  podman run --rm --network chatwoot_internal \
                    --security-opt label=disable \
                    -v "$PWD/smoke_webhook.py:/smoke.py:ro" \
                    -v /root/myaibot-runtime/.env:/runtime/.env:ro \
                    -e SMOKE_ACCOUNT="${ACCOUNT_ID}" \
                    -e SMOKE_CONV="${CONVERSATION_ID}" \
                    docker.io/library/python:3-alpine python /smoke.py
                  rm -f smoke_webhook.py
                '''
            }
        }

        stage('Bot log tail') {
            steps {
                sh '''
                  export CONTAINER_HOST="unix:///run/podman/podman.sock"
                  echo "--- ai-bot recent logs:"
                  podman logs --tail 15 ai-bot || true
                '''
            }
        }
    }
}
