# Deploy pipeline: GitHub → Gitea mirror → Jenkins

```
GitHub (public, source of truth)          your infra
┌──────────────────────┐   pull-mirror   ┌─────────────────────────────┐
│ liodali/myaibot      │ ───────────────▶│ Gitea (internal, read-only  │
│ protected main       │  (polls, RO     │ mirror, + container         │
└──────────────────────┘   token)        │ registry)                   │
                                         └──────────┬──────────────────┘
                                                    │ webhook: push-only,
                                                    │ secret-signed, main only
                                                    ▼
                                         ┌─────────────────────────────┐
                                         │ Jenkins (JCasC-hardened)    │
                                         │ seed.groovy → pipeline job  │
                                         │ analyze → build → push      │
                                         │ → forced-command SSH deploy │
                                         └──────────┬──────────────────┘
                                                    │ pull from Gitea registry
                                                    ▼
                                         ┌─────────────────────────────┐
                                         │ Chatwoot host (podman)      │
                                         │ /opt/myaibot compose stack  │
                                         └─────────────────────────────┘
```

## Security properties of this chain

- **Fork PRs are never built.** The job is a plain pipeline (not multibranch),
  triggered only by `Generic Webhook Trigger` filtered to `refs/heads/main`.
- **The pipeline script is only ever read from the mirror's `main`**
  (`cpsScm → */main`). Forks can edit their Jenkinsfile freely; it never
  reaches our Jenkins.
- **Webhook is secret-validated.** Gitea sends `X-Gitea-Signature`; the GWT
  token credential must match.
- **No secrets in the repo.** Registry creds, deploy key, and webhook token
  live only in Jenkins credentials; `.env` lives only on the server.
- **Deploy key is a forced command.** Even a full Jenkins compromise cannot
  open a shell on the Chatwoot host — it can only run `myaibot-deploy`.
- **Controller runs no builds** (`numExecutors: 0`), anonymous gets nothing.

## 1. GitHub side (already done in-repo)

- Branch protection on `main` (no force-push, no deletion).
- Secret scanning + push protection enabled.
- Dependabot: `pub` + `docker` ecosystems (`.github/dependabot.yml`).

## 2. Gitea: pull mirror + registry + webhook

1. **Mirror**: New Migration → Git → URL
   `https://github.com/liodali/myaibot.git`. Auth: a read-only GitHub
   token (`public_repo` scope is enough for public). Sync interval: 8h+.
   The mirror stays read-only — nobody pushes to it.
2. **Registry**: the built-in Gitea container registry serves this repo at
   `gitea.local:3000/liodali/myaibot`. Create a token (Settings →
   Applications) with `write:package` for the Jenkins push user; store it
   as Jenkins credential `myaibot-registry` (username/password).
3. **Webhook**: repo Settings → Webhooks:
   - Target URL: `http://<jenkins-host>:8080/generic-webhook-trigger/invoke`
   - Content type: `application/json`
   - Secret: the value of Jenkins credential `myaibot-webhook-token`
     (generate: `openssl rand -hex 32`)
   - Trigger on: **Push events only**. Branch filter: `main`.

## 3. Jenkins: JCasC + seed

1. **Plugins**: `configuration-as-code`, `job-dsl`,
   `generic-webhook-trigger`, `git`, `workflow-aggregator`,
   `ansicolor`, `timestamper`, `ws-cleanup`, `ssh-credentials`,
   `credentials-binding`.
2. **JCasC**: point `CASC_JENKINS_CONFIG` at `jenkins/jenkins.yaml`
   (mount it read-only; edit `authorizationStrategy` user + `location.url`).
   Add the non-JCasC flags to `JAVA_ARGS` (documented at the top of that
   file): disable remoting CLI, CSP header, bind to LAN-only address.
3. **Credentials** (System → Global):
   | ID | Type | Value |
   |---|---|---|
   | `myaibot-webhook-token` | Secret text | same secret as Gitea webhook |
   | `myaibot-mirror-clone` | Username/password | read-only mirror account |
   | `myaibot-registry` | Username/password | Gitea token with `write:package` |
   | `myaibot-deploy-ssh` | SSH username w/ private key | the forced-command key below |
4. **Global environment variables** (System → Global properties →
   Environment variables) — the real endpoints. These are read by
   `jenkins/seed.groovy` (GITEA_MIRROR) and the `Jenkinsfile`
   (GITEA_REGISTRY). They live ONLY in the controller, never in the
   public repo:

   | Variable | Example |
   |---|---|
   | `GITEA_MIRROR` | `http://gitea.internal:3000/liodali/myaibot.git` |
   | `GITEA_REGISTRY` | `gitea.internal:3000` |

   Prefer JCasC for it? Point `CASC_JENKINS_CONFIG` at a *directory*
   holding both `jenkins/jenkins.yaml` and a server-local override
   (git-ignored, root-only readable) such as `/var/lib/jenkins/casc/local.yaml`:

   ```yaml
   jenkins:
     globalNodeProperties:
       - environmentVariables:
           env:
             GITEA_MIRROR: "http://gitea.internal:3000/liodali/myaibot.git"
             GITEA_REGISTRY: "gitea.internal:3000"
   ```

5. **Seed job (one-time bootstrap)**: New Item → Freestyle → *seed*.
   Build step "Process Job DSLs" → "Use the provided DSL script" → paste
   `jenkins/seed.groovy`. Run once (approve the script under
   Manage Jenkins → In-process Script Approval if it queues). The
   `myaibot` pipeline job now exists with the injected endpoints;
   future changes flow through git + the seed.

## 4. Chatwoot host: deploy user + forced command

```bash
# Once, on the host:
install -m 755 deploy/myaibot-deploy.sh /usr/local/bin/myaibot-deploy
mkdir -p /opt/myaibot /etc/myaibot && cp deploy/compose.prod.yml /opt/myaibot/docker-compose.yml
# .env (real secrets) lives in /opt/myaibot — never in git.

# Real registry endpoint — lives on the host only, never in the repo:
cat > /etc/myaibot/deploy.env <<'EOF'
REGISTRY="gitea.internal:3000/liodali/myaibot"
EOF
chmod 600 /etc/myaibot/deploy.env

useradd -m myaibot-deploy
# In ~myaibot-deploy/.ssh/authorized_keys (single line):
#   command="/usr/local/bin/myaibot-deploy",no-pty,no-port-forwarding,\
#   no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA... jenkins-deploy
# The matching private key is Jenkins credential `myaibot-deploy-ssh`.
# myaibot-deploy needs podman + network access; grant sudo (NOPASSWD) for
# podman-compose only if you cannot run rootless.
```

## 5. Agent prep (wherever builds run)

The pipeline shells out to **rootless podman** as the agent's OS user:
```bash
sudo dnf install podman
podman login gitea.local:3000   # verify auth works before first build
```
No Docker socket, no root daemon, no host mounts during builds.

## 6. Rolling back

```bash
ssh myaibot-deploy@chatwoot-host "main-abc1234"   # any previous tag
```
Tags are `main-<short sha>`; the last 20 build tags are kept in the registry.
