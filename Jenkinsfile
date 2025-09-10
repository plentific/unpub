pipeline {
  agent {
    kubernetes {
      defaultContainer 'agent'
      // yaml agentPod("2", "8Gi", "2", "8Gi", "jenkins-slave")
      yaml agentPodBuildkit()
    }
  }

  options {
    buildDiscarder(logRotator(daysToKeepStr: '7'))
    timeout(time: 90, unit: 'MINUTES')
  }

  environment {
    ECRURI = '538623626928.dkr.ecr.eu-west-1.amazonaws.com'
    APP = 'unpub'
    AWS_ACCOUNT_ID = "538623626928"
    AWS_REGION = "eu-west-1"
    CLUSTER = "devops-ie-eks-k8s"
    CLUSTER_FOLDER = "devops-ie-eks-k8s"
    ARGOCD_SERVER = "argocd.devops.plentific.com"
    ARGOCD_OPTS = "--grpc-web"
    TASK = "deploy"
    BUILD_ARCH = "amd64"
    JENKINS_SERVICE_ACCOUNT = "jenkins"
    JENKINS_URL_SUPPORT_INSTANCE = "https://jenkins.devops.plentific.com/"
  }

  libraries {
    lib('shared-pipeline-library')
  }

  stages {
    stage ('1. Prepare') {
      steps {
        container('agent') {
          sendNotifications 'STARTED'
        }
      }
    }

    // stage ('2. Build unpub registry') {
    //   when {
    //     expression { env.BRANCH_NAME == 'master' }
    //   }
    //   steps {
    //     container('kaniko') {
    //       sh """
    //         /kaniko/executor \
    //           -f `pwd`/docker/Dockerfile \
    //           -c `pwd` \
    //           --cache=false \
    //           --cache-repo=${env.ECRURI}/kaniko \
    //           --destination=${env.ECRURI}/${env.APP}:dart-${env.GIT_COMMIT}
    //       """
    //     }
    //   }
    // }
    stage ('3. Build and Push Unpub') {
        steps {
            container('agent') {
                sh """
                    docker buildx create --name=kube --driver=kubernetes --platform linux/amd64 --node=buildkit-builder-amd64 --use
                """
                sh """
                    docker buildx build \
                        --progress plain \
                        --file `pwd`/docker/Dockerfile \
                        --platform="linux/amd64" \
                        --output type=docker,dest=$WORKSPACE/$APP-$BUILD_ARCH-$APP_TAR_TAG \
                        `pwd`
                """
                sh """
                    ls -lah $WORKSPACE/
                """
                script {
                    env.DEVOPS_ECR_REGISTRY_PASSWORD = sh(returnStdout: true, script: "aws ecr get-login-password --region ${env.AWS_REGION}").trim()
                    print("Check if artifact exists in devops-ie account ECR repository")
                    env.CHECK_IF_ARTIFACT_EXISTS = sh(
                        returnStdout: true,
                        script: "aws ecr batch-get-image --registry-id=${env.AWS_ACCOUNT_ID} --repository-name=${env.APP} --image-ids=imageTag=dart-${env.GIT_COMMIT} --query 'images[].imageId.imageTag' --output text --region ${env.AWS_REGION}"
                        ).trim()
                    println("CHECK_IF_ARTIFACT_EXISTS: ${env.CHECK_IF_ARTIFACT_EXISTS}")
                }
            }
            container('crane'){
                script {
                    if (env.CHECK_IF_ARTIFACT_EXISTS == "") {
                        sh(script: "crane auth login -u AWS -p ${env.DEVOPS_ECR_REGISTRY_PASSWORD} ${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com")
                        sh(returnStdout: true, script: "crane push $WORKSPACE/$APP-$BUILD_ARCH-$APP_TAR_TAG ${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com/$APP:dart-${env.GIT_COMMIT}")
                    }else{
                        print("Artifact image ${env.CHECK_IF_ARTIFACT_EXISTS} already exists in ECR, skipping push.")
                    }
                }
            }
        }
    } // stage

    stage ('3. Update git repository') {
      when {
        expression { env.BRANCH_NAME == 'master' }
      }
      steps {
        container('agent') {
          script {
            withCredentials([usernamePassword(credentialsId: 'github1', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
              git branch: 'master', credentialsId: 'github1', url: 'https://github.com/plentific/devops-cd.git'

              sh """
                git config --global user.email "devops+jenkinsci1@plentific.com"
                git config --global user.name "jenkinsci"
              """

              sh """
                success=0; attempts=0;
                until \$success || [ \$attempts = 20 ]; do
                  let ++attempts;
                  git pull https://$GIT_USERNAME:$GIT_PASSWORD@github.com/plentific/devops-cd.git --rebase || echo "Don't need rebase";
                  echo "BEFORE UPDATE"
                  cat deployment/clusters/${env.CLUSTER_FOLDER}/${env.APP}.yaml
                  config=\$(yq e ".spec.source.helm.values" deployment/clusters/${env.CLUSTER_FOLDER}/${env.APP}.yaml | yq e '(.image.tag = "dart-${env.GIT_COMMIT}")' -) yq e -i '.spec.source.helm.values=strenv(config)' deployment/clusters/${env.CLUSTER_FOLDER}/${env.APP}.yaml
                  echo "AFTER UPDATE"
                  cat deployment/clusters/${env.CLUSTER_FOLDER}/${env.APP}.yaml
                  git add deployment/clusters/${env.CLUSTER_FOLDER}/${env.APP}.yaml
                  commit=\$(git commit -m "[${env.BUILD_NUMBER}] -> ${env.APP}:${env.GIT_COMMIT}" || echo "No git commit needed")
                  result=\$(echo "Everything up-to-date" && git push https://$GIT_USERNAME:$GIT_PASSWORD@github.com/plentific/devops-cd.git HEAD:master || echo "Failed to push")
                  echo "AFTER TRY PUSH TO GIT"
                  cat deployment/clusters/${env.CLUSTER_FOLDER}/${env.APP}.yaml
                  if [ "\$result" == "Everything up-to-date" ]; then
                    echo "Everything up-to-date"
                    break
                  fi
                  if [ "\$commit" == "No git commit needed" ]; then
                    echo "No git commit needed"
                    break
                  fi
                  sleep 3;
                done;
                if ! \$success; then
                  echo "Gave up after \$attempts attempts";
                fi
              """
            }
          }
        }
      }
    }

    stage ('4. Sync data with ArgoCD') {
      when {
        expression { env.BRANCH_NAME == 'master' }
      }
      steps {
        container('agent') {
          script {
            withCredentials([usernamePassword(credentialsId: "argocd-${env.CLUSTER}", usernameVariable: 'ARGOCD_USERNAME', passwordVariable: 'ARGOCD_PASSWORD')]) {
              env.ARGOCD_AUTH_TOKEN = sh(script: "curl -s https://${env.ARGOCD_SERVER}/api/v1/session -d \$'{\"username\":\"$ARGOCD_USERNAME\",\"password\":\"$ARGOCD_PASSWORD\"}' | sed -e 's/[{}]/''/g' | awk -F: '{print \$2}' | sed 's/\\\"//g'", returnStdout: true).trim()
              sh """                
                set +x
                
                #kubectl --context ${env.CLUSTER} apply -f deployment/clusters/${env.CLUSTER_FOLDER}/${env.APP}.yaml -n argocd
                echo "1.Terminate current sync operation"
                argocd app terminate-op ${env.APP} && echo "Terminate current sync for ${env.APP} app" || echo "Don't need terminate ${env.APP} app"
                echo "2. Sync application"
                argocd app sync ${env.APP} --force --prune && echo "Run sync ${env.APP} application" || echo "Don't need sync ${env.APP} app"
                argocd app wait ${env.APP} --timeout 600 
              """
            }
          }
        }
      }
    }

  }

  post {
    always {
      sendNotifications currentBuild.result
    }
  }
}