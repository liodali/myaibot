// Job DSL seed — generates the MyAIBot pipeline job.
//
// SECURITY MODEL (enforced here, not in the Jenkinsfile):
//   1. Pipeline definition is read from the GITEA MIRROR, branch main only
//      ("*/main"). Forks and PRs can never inject code into our Jenkins.
//   2. The ONLY trigger is a Generic Webhook Trigger validated against a
//      secret token (credential `myaibot-webhook-token`), filtered to
//      `refs/heads/main` pushes. No PR events, no branch scanning —
//      this is deliberately NOT a multibranch job.
//   3. PRs from forks are simply never built. Fork users adapt the
//      Jenkinsfile inside their fork for their own infra.
//   4. NO real hostnames here. GITEA_MIRROR / GITEA_REGISTRY are injected
//      from Jenkins global environment variables (Manage Jenkins →
//      System → Global properties, or a server-local JCasC override file —
//      see docs/deploy.md). Only placeholders live in this public repo.
//
// Bootstrap (one-time, see docs/deploy.md): create a freestyle job, add
// "Process Job DSLs" → "Use the provided DSL script" → point at this file.
// After that, job changes flow through git + this seed.

import jenkins.model.Jenkins
import hudson.slaves.EnvironmentVariablesNodeProperty

def globalEnv = Jenkins.instance
    .getGlobalNodeProperties()
    .get(EnvironmentVariablesNodeProperty)
    ?.envVars

// Injected from Jenkins global env; placeholders keep the seed valid for
// fork users running their own Jenkins without our variables.
def GITEA_MIRROR = globalEnv?.get('GITEA_MIRROR')
    ?: 'http://gitea.local:3000/liodali/myaibot.git'
def GITEA_REGISTRY = globalEnv?.get('GITEA_REGISTRY') ?: 'gitea.local:3000'

pipelineJob('myaibot') {
    displayName('MyAIBot')
    description(
        'Chatwoot AI agent bot — build & deploy. ' +
        'Triggers ONLY on pushes to main of the Gitea mirror. ' +
        'Never builds fork PRs.'
    )

    logRotator {
        numToKeep(20)
    }

    properties {
        disableConcurrentBuilds()
        // Re-run this seed when it changes.
        // (Seed job updates pipeline jobs; keeps everything as code.)
    }

    parameters {
        // Allow manual deploys of an existing tag without a push.
        stringParam('DEPLOY_TAG', '', 'Existing image tag to redeploy (leave empty on webhook builds)')
    }

    triggers {
        genericTrigger {
            genericVariables {
                genericVariable {
                    key('GITEA_REF')
                    value('$.ref')
                    expressionType('JSONPath')
                }
                genericVariable {
                    key('GITEA_AFTER')
                    value('$.after')
                    expressionType('JSONPath')
                }
            }
            genericHeaderVariables {
                genericHeaderVariable {
                    key('X-Gitea-Event')
                }
            }
            // Secret token lives in the Jenkins credential below; the same
            // value is set as the Gitea webhook's secret. GWT rejects
            // requests that do not carry it.
            tokenCredentialId('myaibot-webhook-token')
            causeString('Push to $GITEA_REF ($GITEA_AFTER)')
            printContributedVariables(false)
            printPostContent(false)
            // THE gate: only main-branch pushes reach the build.
            regexpFilterText('$GITEA_REF')
            regexpFilterExpression('^refs/heads/main$')
        }
    }

    definition {
        cpsScm {
            scm {
                git {
                    remote {
                        url(GITEA_MIRROR)
                        // Read-only mirror account (no write access needed).
                        credentials('myaibot-mirror-clone')
                    }
                    branches {
                        branchName('*/main')
                    }
                    extensions {
                        cleanBeforeCheckout()
                        cloneOption {
                            shallow(true)
                            depth(1)
                            noTags(true)
                            timeout(5)
                        }
                    }
                }
            }
            scriptPath('Jenkinsfile')
            lightweight(true)
        }
    }
}
