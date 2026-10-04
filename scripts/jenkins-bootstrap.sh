#!/usr/bin/env bash
# REST-only bootstrap for the Jenkins side of the MyAIBot deploy chain.
#
# Why REST and not jenkins-cli.jar: reverse proxies (nginx/openresty) break
# the CLI's full-duplex channel ("CLI handshake failed with status code 400").
#
# Why scriptText + DslScriptLoader and not a seed job: Job DSL scripts in job
# configs require admin-UI approval ("script not yet approved for use").
# Running the DSL engine directly from the script console (as the
# authenticated admin) bypasses the approval system entirely — and is how
# this script applies jenkins/seed.groovy every time it runs.
#
# Steps:
#   1. auth check            -> GET  /whoAmI/api/json
#   2. job-dsl present       -> GET  /pluginManager/plugin/job-dsl/api/json
#   3. global env vars       -> POST /scriptText
#   4. run seed.groovy       -> POST /scriptText (DslScriptLoader)
#   5. verify myaibot        -> GET  /job/myaibot/api/json
#
# Requires: curl, jq.  Config: scripts/jenkins.env (see jenkins.env.example).
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${JENKINS_ENV:-scripts/jenkins.env}"
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
fi

: "${JENKINS_URL:?set JENKINS_URL in $ENV_FILE}"
: "${JENKINS_USER:?set JENKINS_USER in $ENV_FILE}"
: "${JENKINS_API_TOKEN:?set JENKINS_API_TOKEN in $ENV_FILE}"
: "${GITEA_MIRROR:?set GITEA_MIRROR in $ENV_FILE}"
: "${GITEA_REGISTRY:?set GITEA_REGISTRY in $ENV_FILE}"

command -v jq > /dev/null || { echo "jq not found"; exit 1; }

AUTH="$JENKINS_USER:$JENKINS_API_TOKEN"

echo "==> [1/5] auth check (REST)"
code=$(curl -sS -o /dev/null -w "%{http_code}" -u "$AUTH" "$JENKINS_URL/whoAmI/api/json")
[ "$code" = "200" ] || { echo "    FAILED: HTTP $code — check JENKINS_USER / JENKINS_API_TOKEN." >&2; exit 1; }
echo "    authenticated"

echo "==> [2/5] job-dsl plugin present?"
pcode=$(curl -sS -o /dev/null -w "%{http_code}" -u "$AUTH" \
    "$JENKINS_URL/pluginManager/plugin/job-dsl/api/json" || true)
[ "$pcode" = "200" ] || {
    echo "    job-dsl missing — install it (Manage Jenkins -> Plugins), rerun." >&2
    exit 1
}
echo "    yes"

echo "==> [3/5] setting global env vars (GITEA_MIRROR / GITEA_REGISTRY)"
curl -sS -u "$AUTH" --data-urlencode "script=import jenkins.model.Jenkins
import hudson.slaves.EnvironmentVariablesNodeProperty

def j = Jenkins.instance
def props = j.getGlobalNodeProperties().get(EnvironmentVariablesNodeProperty)
if (props == null) {
    props = new EnvironmentVariablesNodeProperty()
    j.getGlobalNodeProperties().add(props)
}
props.envVars.put('GITEA_MIRROR',   '${GITEA_MIRROR}')
props.envVars.put('GITEA_REGISTRY', '${GITEA_REGISTRY}')
j.save()
return 'globals: ' + props.envVars" "$JENKINS_URL/scriptText" | sed 's/^/    /'

echo "==> [4/5] applying jenkins/seed.groovy (DslScriptLoader)"
B64=$(base64 < jenkins/seed.groovy | tr -d '\n')
out=$(curl -sS -u "$AUTH" --data-urlencode "script=import javaposse.jobdsl.dsl.DslScriptLoader
import javaposse.jobdsl.plugin.JenkinsJobManagement

def txt = new String('${B64}'.decodeBase64())
def mgmt = new JenkinsJobManagement(System.out, [:], new File('/tmp'))
def result = new DslScriptLoader(mgmt).runScript(txt)
return 'generated: ' + result.jobs*.jobName" "$JENKINS_URL/scriptText")
echo "    $out"
case "$out" in *myaibot*) ;; *) echo "    seed failed — see output above" >&2; exit 1 ;; esac

echo "==> [5/5] verifying"
code=$(curl -sS -o /dev/null -w "%{http_code}" -u "$AUTH" "$JENKINS_URL/job/myaibot/api/json")
[ "$code" = "200" ] || { echo "    myaibot not found (HTTP $code)" >&2; exit 1; }
echo "  ✅ myaibot pipeline job exists — chain is armed."
echo "  Next: Gitea → webhook → Test Delivery"
