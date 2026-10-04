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
                                         │ Jenkins (hardened via UI)    │
                                         │ seed.groovy → pipeline job  │
                                         │ analyze → build → push      │
                                         │ → podman-socket deploy      │
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
- **Webhook is token-gated.** Only requests carrying the secret token in
  the invoke URL (`?token=...`) match the job. Gitea's `X-Gitea-Signature`
  is not verified by GWT — LAN-only reachability is the outer wall.
- **No secrets in the repo.** Registry creds, deploy key, and webhook token
  live only in Jenkins credentials; `.env` lives only on the server.
- **Deploy runs over the agent's podman socket** (same VPS as Chatwoot —
  no SSH, no deploy user). The socket is the trust boundary: whoever
  controls Jenkins controls all containers on that host. Treat the
  controller's security accordingly.
- **Controller runs no builds** (executors: 0 via UI — see checklist),
  anonymous gets nothing.

## 1. GitHub side (already done in-repo)

- Branch protection on `main` (no force-push, no deletion).
- Secret scanning + push protection enabled.
- Dependabot: `pub` + `docker` ecosystems (`.github/dependabot.yml`).

## 2. Gitea: pull mirror + registry + webhook

Fastest path — one idempotent script (requires `curl` + `jq`):

```bash
cp scripts/gitea.env.example scripts/gitea.env
# edit scripts/gitea.env: GITEA_URL, GITEA_TOKEN, OWNER, JENKENS_WEBHOOK_URL
bash scripts/gitea-setup.sh
```

It creates the mirror, the webhook, and forces a first sync — safe to
re-run. Manual equivalents below.

1. **Mirror**: New Migration → Git → URL
   `https://github.com/liodali/myaibot.git`. Auth: a read-only GitHub
   token (`public_repo` scope is enough for public). Sync interval: 8h+.
   The mirror stays read-only — nobody pushes to it.
   CLI equivalent (`tea` has no mirror support — use the API):

   ```bash
   curl -X POST "http://<gitea>:3000/api/v1/repos/migrate" \
     -H "Authorization: token $GITEA_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "clone_addr": "https://github.com/liodali/myaibot.git",
       "repo_owner": "<owner>",
       "repo_name": "myaibot",
       "mirror": true,
       "mirror_interval": "8h0m0s",
       "service": "github",
       "private": true
     }'

   # force an instant sync later (≈ "Synchronize Now"):
   curl -X POST "http://<gitea>:3000/api/v1/repos/<owner>/myaibot/mirror-sync" \
     -H "Authorization: token $GITEA_TOKEN"
   ```
2. **Registry**: the built-in Gitea container registry serves this repo at
   `<host[:port]>/<owner>/myaibot`. Create a token (Settings →
   Applications) with `write:package` for the Jenkins push user; store it
   as Jenkins credential `myaibot-registry` (username/password).
3. **Webhook**: repo Settings → Webhooks:
   - Target URL:
     `http://<jenkins-host>:8080/generic-webhook-trigger/invoke?token=<TOKEN>`
     where `<TOKEN>` is the value of Jenkins credential
     `myaibot-webhook-token` (generate: `openssl rand -hex 32`).
     **GWT matches jobs by this token** — no token in the URL, no job
     selected, nothing happens.
   - Content type: `application/json`
   - Secret field: optional. Gitea uses it to send an `X-Gitea-Signature`
     HMAC header, which GWT does not verify — the `?token=` in the URL is
     the authentication. This is why the endpoint must stay LAN-only.
   - Trigger on: **Push events only**. Branch filter: `main`.
   CLI equivalent (API — webhooks are also not covered by `tea`):

   ```bash
   curl -X POST "http://<gitea>:3000/api/v1/repos/<owner>/myaibot/webhooks" \
     -H "Authorization: token $GITEA_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "type": "gitea",
       "active": true,
       "events": ["push"],
       "branch_filter": "main",
       "config": {
         "url": "http://<jenkins>:8080/generic-webhook-trigger/invoke?token=<TOKEN>",
         "content_type": "json",
         "http_method": "POST"
       }
     }'
   ```

## 3. Jenkins: hardening + seed

1. **Plugins**: `job-dsl`,
   `generic-webhook-trigger`, `git`, `workflow-aggregator`,
   `ansicolor`, `timestamper`, `ws-cleanup`, `ssh-credentials`,
   `credentials-binding`.
2. **Hardening** (one-time, via the UI — Manage Jenkins → Security):
   - Matrix-based authorization: your user → Administer; authenticated →
     Overall/Read, Job/Read, Job/Build; **anonymous gets nothing**.
   - Set **Number of executors to 0** on the controller — builds run on
     agents only.
   - Markup formatter: **plain text** (kills description XSS).
   - Disable the inbound agent port if you don't use inbound agents.
   - Keep CSRF protection on (default) — never disable crumbs.
   - In the systemd unit / container env (`JAVA_ARGS`):
     `-Djenkins.CLI.disabled=true` (kill remoting CLI) and bind the HTTP
     listener to LAN/localhost only, or put Jenkins behind Tailscale.
4. **Credentials** (System → Global):
   | ID | Type | Value |
   |---|---|---|
   | `myaibot-webhook-token` | Secret text | same secret as Gitea webhook |
   | `myaibot-mirror-clone` | Username/password | read-only mirror account |
   | `myaibot-registry` | Username/password | Gitea token with `write:package` |
5. **Global environment variables** (System → Global properties →
   Environment variables) — the real endpoints. These are read by
   `jenkins/seed.groovy` (GITEA_MIRROR) and the `Jenkinsfile`
   (GITEA_REGISTRY). They live ONLY in the controller, never in the
   public repo:

   | Variable | Example |
   |---|---|
   | `GITEA_MIRROR` | `http://gitea.internal:3000/<owner>/myaibot.git` |
   | `GITEA_REGISTRY` | `gitea.internal:3000/<owner>/myaibot` (full namespace: host + owner + repo) |

6. **Seed job (one-time bootstrap)**: New Item → Freestyle → *seed*.
   Build step "Process Job DSLs" → "Use the provided DSL script" → paste
   `jenkins/seed.groovy`. Run once (approve the script under
   Manage Jenkins → In-process Script Approval if it queues). The
   `myaibot` pipeline job now exists with the injected endpoints;
   future changes flow through git + the seed.

## 4. Runtime layout (created by the pipeline itself)

No host setup required. The Deploy stage talks to the podman socket the
Jenkins agent already has (`CONTAINER_HOST` auto-detected; override with the
`PODMAN_SOCK` global env), pulls the image with `--creds`, and runs:

```
~/myaibot-runtime/.env                  # bot secrets, copied from the
                                        # myaibot-botenv file credential
podman run -d --name ai-bot \
  --network chatwoot_internal --network-alias ai-bot \
  --restart always --env-file ~/myaibot-runtime/.env \
  gitea.<host>/<owner>/myaibot:<tag>
```

`deploy/compose.prod.yml` remains in the repo for humans preferring compose.

## 5. Agent prep (wherever builds run)

The pipeline shells out to **rootless podman** as the agent's OS user:
```bash
sudo dnf install podman
podman login gitea.local:3000   # verify auth works before first build
```
No Docker socket, no root daemon, no host mounts during builds.

## 6. Rolling back

Run the `myaibot` job with the `DEPLOY_TAG` parameter set to any previous
tag (e.g. `main-abc1234`); the Deploy stage rolls that image out instead.
Tags are `main-<short sha>`; the last 20 are kept in the registry.
