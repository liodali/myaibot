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
        ansiColor('xterm')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timeout(time: 15, unit: 'MINUTES')
    }

    environment {
        // GITEA_REGISTRY comes from Jenkins GLOBAL environment variables
        // (Manage Jenkins → System → Global properties) — set it there,
        // never in this public file. GITEA_MIRROR is likewise global-env
        // (used by the seed job).
        IMAGE = "${env.GITEA_REGISTRY}/liodali/myaibot"
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
                }
            }
        }

        stage('Analyze') {
            steps {
                sh '''
                  podman run --rm -v "$PWD":/app -w /app dart:stable \
                    sh -c "dart pub get && dart analyze --fatal-infos"
                '''
            }
        }

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
                      podman login "$GITEA_REGISTRY" \
                        -u "$REG_USER" --password-stdin <<< "$REG_PASS"
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
                      ssh -i "$DEPLOY_KEY" \
                          -o StrictHostKeyChecking=accept-new \
                          myaibot-deploy@localhost "$TAG"
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
