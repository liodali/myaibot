pipeline {
    agent any
    options { timestamps(); timeout(time: 3, unit: 'MINUTES') }
    stages {
        stage('probe') {
            steps {
                sh '''
                  export CONTAINER_HOST="unix:///run/podman/podman.sock"
                  echo "--- who listens on 3100 / 3000:"
                  ss -ltnp | grep -E ':3100|:3000' || echo "nothing"
                  echo "--- ai-bot containers (any state):"
                  podman ps -a --format "{{.Names}} | {{.Status}} | {{.Ports}}" | grep -E 'ai-bot|NAME' || echo none
                '''
            }
        }
    }
}
