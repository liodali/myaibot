// One-shot (rerunnable) host setup for the MyAIBot deploy target.
// Runs ON the Chatwoot host via the Jenkins agent (same VPS).
//
// What it does — see docs/deploy.md section 4:
//   - myaibot-deploy user + forced-command SSH key
//   - /usr/local/bin/myaibot-deploy (the only thing that key can run)
//   - /etc/myaibot/deploy.env (real registry endpoint)
//   - /opt/myaibot compose stack + bot .env (from `myaibot-botenv` credential)
//   - registry login for the deploy user
//   - reports chatwoot network topology (rootful vs rootless)
//
// Idempotent: safe to re-run after editing .env or rotating keys.

pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 10, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    stages {
        stage('Preflight') {
            steps {
                sh '''
                  sudo -n true || {
                    echo "NO PASSWORDLESS SUDO for the agent user." >&2
                    echo "Either grant it, or run the setup by hand (docs/deploy.md section 4)." >&2
                    exit 1
                  }
                  command -v podman-compose >/dev/null || {
                    echo "podman-compose not found on host" >&2; exit 1; }
                '''
            }
        }

        stage('Deploy user + forced command') {
            steps {
                sh '''
                  set -e
                  id myaibot-deploy >/dev/null 2>&1 || sudo useradd -m myaibot-deploy
                  sudo mkdir -p /home/myaibot-deploy/.ssh
                  echo 'command="/usr/local/bin/myaibot-deploy",no-pty,no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICOmx1+U2VOISnMDelo8rOP/KWkT5KGJsNSjstyrLqI myaibot-jenkins-deploy-v2' \
                    | sudo tee /home/myaibot-deploy/.ssh/authorized_keys >/dev/null
                  sudo chmod 700 /home/myaibot-deploy/.ssh
                  sudo chmod 600 /home/myaibot-deploy/.ssh/authorized_keys
                  sudo chown -R myaibot-deploy: /home/myaibot-deploy/.ssh
                  sudo install -m 755 deploy/myaibot-deploy.sh /usr/local/bin/myaibot-deploy
                '''
            }
        }

        stage('Registry endpoint + compose') {
            steps {
                sh '''
                  set -e
                  sudo mkdir -p /etc/myaibot /opt/myaibot
                  echo "REGISTRY=\\"$GITEA_REGISTRY\\"" | sudo tee /etc/myaibot/deploy.env >/dev/null
                  sudo chown root:myaibot-deploy /etc/myaibot/deploy.env
                  sudo chmod 640 /etc/myaibot/deploy.env
                  sudo cp deploy/compose.prod.yml /opt/myaibot/docker-compose.yml
                  sudo chown -R myaibot-deploy: /opt/myaibot
                '''
            }
        }

        stage('Bot secrets (.env)') {
            steps {
                withCredentials([file(credentialsId: 'myaibot-botenv', variable: 'ENVFILE')]) {
                    sh '''
                      sudo cp "$ENVFILE" /opt/myaibot/.env
                      sudo chown myaibot-deploy: /opt/myaibot/.env
                      sudo chmod 600 /opt/myaibot/.env
                    '''
                }
            }
        }

        stage('Registry login (deploy user)') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'myaibot-registry',
                    usernameVariable: 'REG_USER',
                    passwordVariable: 'REG_PASS')]) {
                    sh '''
                      set -e
                      REGISTRY_HOST="${GITEA_REGISTRY%%/*}"
                      printf '%s' "$REG_PASS" | sudo -u myaibot-deploy \
                        podman login "$REGISTRY_HOST" -u "$REG_USER" --password-stdin
                    '''
                }
            }
        }

        stage('Topology report') {
            steps {
                sh '''
                  echo "--- chatwoot network (root podman):"
                  sudo podman network ls | grep -i chatwoot || echo "none (root)"
                  echo "--- chatwoot network (rootless myaibot-deploy):"
                  sudo -u myaibot-deploy podman network ls 2>/dev/null | grep -i chatwoot || echo "none (deploy user)"
                  echo "--- chatwoot containers (root):"
                  sudo podman ps --format "{{.Names}}" | grep -i chatwoot | head -5 || true
                '''
            }
        }
    }
}
