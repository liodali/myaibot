pipeline {
    agent any
    options { timestamps(); timeout(time: 5, unit: 'MINUTES') }
    stages {
        stage('probe') {
            steps {
                sh '''
                  export CONTAINER_HOST="unix:///run/podman/podman.sock"
                  echo "--- chatwoot containers (name / ports):"
                  podman ps --format "{{.Names}} | {{.Ports}}" | grep -i chatwoot || echo none
                  echo "--- all networks:"
                  podman network ls | head -8
                  echo "--- who is on chatwoot_internal:"
                  podman network inspect chatwoot_internal --format "{{range .Containers}}{{.Name}} {{end}}" 2>/dev/null || echo "network not found"
                '''
            }
        }
    }
}
