#!/usr/bin/env bash
# CLI bootstrap for the Jenkins side of the MyAIBot deploy chain — no UI needed.
#
# Does, in order:
#   1. verifies Jenkins auth (whoami)
#   2. sets global env vars GITEA_MIRROR / GITEA_REGISTRY (controller-side)
#   3. creates or updates the "seed" job with jenkins/seed.groovy embedded
#   4. builds it, auto-approves the pending Job DSL script, rebuilds
#   5. verifies the "myaibot" pipeline job now exists
#
# Requires: java (jenkins-cli.jar), curl.
# Config: scripts/jenkins.env (see jenkins.env.example). GITEA_ENV-style
# override: JENKINS_ENV=path/to/file.
#
# NOTE: if you applied the hardening flag -Djenkins.CLI.disabled=true,
# the CLI is off — use the UI path in docs/deploy.md instead.
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

command -v java > /dev/null || { echo "java not found (brew install openjdk)"; exit 1; }

CLI=/tmp/jenkins-cli.jar
echo "==> [1/5] fetching jenkins-cli.jar"
curl -sSf -o "$CLI" "$JENKINS_URL/jnlpJars/jenkins-cli.jar"

jc() {
    java -jar "$CLI" -s "$JENKINS_URL" \
         -auth "$JENKINS_USER:$JENKINS_API_TOKEN" "$@"
}

echo "==> [2/5] auth check"
echo "    logged in as: $(jc whoami)"
if ! jc list-plugins 2>/dev/null | grep -q '^job-dsl '; then
    echo "    WARNING: job-dsl plugin not found — install it (Manage Jenkins → Plugins) and rerun" >&2
fi

echo "==> [3/5] setting global env vars"
jc groovy = <<EOF
import jenkins.model.Jenkins
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
println '    GITEA_MIRROR='   + props.envVars.get('GITEA_MIRROR')
println '    GITEA_REGISTRY=' + props.envVars.get('GITEA_REGISTRY')
EOF

echo "==> [4/5] creating/updating seed job"
# Embed seed.groovy into a freestyle config.xml (XML-escaped)
python3 - "$ENV_FILE" <<'PYEOF'
import sys
from xml.sax.saxutils import escape
seed = open('jenkins/seed.groovy').read()
config = f"""<?xml version='1.1' encoding='UTF-8'?>
<project>
  <description>Job DSL seed — regenerates the myaibot pipeline job. Re-run after editing jenkins/seed.groovy.</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <scm class="hudson.scm.NullSCM"/>
  <canRoam>true</canRoam>
  <disabled>false</disabled>
  <blockBuildWhenDownstreamBuilding>false</blockBuildWhenDownstreamBuilding>
  <blockBuildWhenUpstreamBuilding>false</blockBuildWhenUpstreamBuilding>
  <triggers/>
  <concurrentBuild>false</concurrentBuild>
  <builders>
    <javaposse.jobdsl.plugin.ExecuteDslScripts plugin="job-dsl">
      <targets></targets>
      <usingScriptText>true</usingScriptText>
      <scriptText>{escape(seed)}</scriptText>
      <ignoreExisting>false</ignoreExisting>
      <removedJobAction>IGNORE</removedJobAction>
      <removedViewAction>IGNORE</removedViewAction>
      <lookupStrategy>JENKINS_ROOT</lookupStrategy>
      <sandbox>true</sandbox>
    </javaposse.jobdsl.plugin.ExecuteDslScripts>
  </builders>
  <publishers/>
  <buildWrappers/>
</project>
"""
open('/tmp/seed-config.xml', 'w').write(config)
PYEOF

if jc list-jobs | grep -qx 'seed'; then
    jc update-job seed < /tmp/seed-config.xml
    echo "    seed job updated"
else
    jc create-job seed < /tmp/seed-config.xml
    echo "    seed job created"
fi
rm -f /tmp/seed-config.xml

echo "==> [5/5] building seed (approve + rebuild)"
jc build seed -s || echo "    (first build queued the script for approval — expected)"
jc groovy = <<'EOF'
import org.jenkinsci.plugins.scriptsecurity.scripts.ScriptApproval
def sa = ScriptApproval.get()
sa.pendingScripts.each { s ->
    sa.approveScript(s.hash)
    println '    approved: ' + s.hash
}
EOF
jc build seed -s

echo
echo "Result:"
if jc list-jobs | grep -qx 'myaibot'; then
    echo "  ✅ myaibot pipeline job exists — chain is armed."
    echo "  Next: Gitea → medali/myaibot → Settings → Webhooks → Test Delivery"
else
    echo "  ❌ myaibot not found — check the seed build log in Jenkins." >&2
    exit 1
fi
