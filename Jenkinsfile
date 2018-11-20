pipeline {
    agent {
        label 'bb5'
    }

    options {
        timestamps()
    }

    environment {
        DEPLOYMENT_ROOT = "/gpfs/bbp.epfl.ch/apps/hpc/test/jenkins/deployment"
    }

    stages {
        stage('Compilers') {
            steps {
                dir("deploy") {
                    sh "./deploy.sh compilers"
                }
            }

            post {
                always {
                    junit testResults: 'deploy/compilers.xml', allowEmptyResults: true
                }
            }
        }

        stage('Tools') {
            steps {
                dir("deploy") {
                    sh "./deploy.sh tools"
                }
            }

            post {
                always {
                    junit testResults: 'deploy/tools.xml', allowEmptyResults: true
                }
            }
        }

        stage('Libraries') {
            steps {
                dir("deploy") {
                    sh "./deploy.sh libraries"
                }
            }

            post {
                always {
                    junit testResults: 'deploy/libraries.xml', allowEmptyResults: true
                }
            }
        }

        stage('Applications') {
            steps {
                dir("deploy") {
                    sh "./deploy.sh applications"
                }
            }

            post {
                always {
                    junit testResults: 'deploy/applications.xml', allowEmptyResults: true
                }
            }
        }

        stage('Deployment') {
            steps {
                sh "ls"
            }
        }
    }
}
