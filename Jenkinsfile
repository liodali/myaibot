// MyAIBot CI/CD pipeline.
//
// SECURITY MODEL — read before editing:
//  - Our Jenkins loads this file ONLY from the Gitea mirror's main branch
//    (see jenkins/seed.groovy). It is never built from fork PRs — the job
//    has no PR triggers at all, and the webhook filter only accepts pushes
//    to refs/heads/main.
//  - Forks: feel free to adapt this to your infra or delete it. It will
//    never run on our Jenkins from your copy.
//  - No secrets live in this file. Registry creds and the deploy SSH key are
//    Jenkins credentials, injected only in the stages that need them.
//
// Runs on a host agent with rootless podman (see docs/deploy.md).

pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 15, unit: 'MINUTES')
    }

    environment {
        // GITEA_REGISTRY is the FULL image namespace (host + owner/repo),
        // set as a Jenkins global env variable — e.g. "gitea:3000/<owner>/myaibot".
        // Never real values in this public file.
        IMAGE = "${env.GITEA_REGISTRY}"
        TAG = "main-${env.GIT_COMMIT?.take(7) ?: 'untagged'}"
    }

    stages {
        stage('Preflight') {
            steps {
                script {
                    if (!env.GITEA_REGISTRY?.trim()) {
                        error('GITEA_REGISTRY is not set. Add it as a Jenkins ' +
                              'global environment variable (see docs/deploy.md).')
                    }
                    if (!env.GITEA_REGISTRY.contains('/')) {
                        error('GITEA_REGISTRY must be the full namespace: ' +
                              '<host[:port]>/<owner>/<repo> — e.g. gitea:3000/<owner>/myaibot')
                    }
                }
            }
        }

        // Analysis runs inside the image build (see Dockerfile: dart
        // analyze gates the compile) — no workspace bind-mounts, which
        // rootless podman on RHEL rejects (statfs ENOENT).

        stage('Build image') {
            steps {
                // amd64 explicitly: agents may be arm64, prod is x86.
                sh '''
                  podman build \
                    --platform linux/amd64 \
                    --layers \
                    -t "$IMAGE:$TAG" \
                    -t "$IMAGE:latest" \
                    .
                '''
            }
        }

        stage('Push to Gitea registry') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'myaibot-registry',
                    usernameVariable: 'REG_USER',
                    passwordVariable: 'REG_PASS')]) {
                    sh '''
                      # login needs the registry HOST only (no namespace path)
                      REGISTRY_HOST="${GITEA_REGISTRY%%/*}"
                      printf '%s' "$REG_PASS" | podman login "$REGISTRY_HOST" \
                        -u "$REG_USER" --password-stdin
                      podman push "$IMAGE:$TAG"
                      podman push "$IMAGE:latest"
                    '''
                }
            }
        }

        stage('Deploy') {
            input {
                message 'Deploy to production?'
                ok 'Deploy'
            }
            steps {
                // SSH key is a forced-command key: even if leaked from
                // Jenkins, it can only run the deploy script, nothing else.
                withCredentials([sshUserPrivateKey(
                    credentialsId: 'myaibot-deploy-ssh',
                    keyFileVariable: 'DEPLOY_KEY')]) {
                    sh '''
                      DEPLOY_HOST="${DEPLOY_HOST:-localhost}"
                      ssh -i "$DEPLOY_KEY" \
                          -o StrictHostKeyChecking=accept-new \
                          myaibot-deploy@"$DEPLOY_HOST" "$TAG"
                    '''
                }
            }
        }
    }

    post {
        always {
            // Keep the agent's image cache bounded.
            sh 'podman image prune -f --filter "until=168h" || true'
            cleanWs()
        }
    }
}
