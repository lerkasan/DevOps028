#!/usr/bin/env bash

# Requires one argument:
# string $1 - name of parameter in EC2 parameter store
function get_from_parameter_store {
    aws ssm get-parameter --name $1 --with-decryption --output text | awk '{print $4}'
}

# Requires three arguments:
# string $1 - URL of file to be downloaded
# string $2 - full path to folder where downloaded file should be saved
# int $3    - number of download retries
function download_from_s3 {
    let RETRIES=$3
    until [ ${RETRIES} -lt 0 ] || [ -e "$2" ]; do
        aws s3 cp $1 $2
        let "RETRIES--"
        sleep 5
    done
    if [ ! -e "$2" ]; then
        echo "An error occurred during downloading file by URL $1"
        exit 1
    fi
}

export AWS_DEFAULT_REGION="us-west-2"
export AWS_SECRET_ACCESS_KEY=`get_from_parameter_store "jenkins_secret_access_key"`
export AWS_ACCESS_KEY_ID=`get_from_parameter_store "jenkins_access_key_id"`

export CLUSTER_NAME=`get_from_parameter_store "demo3_cluster_name"`
export KOPS_STATE_STORE=`get_from_parameter_store "demo3_kops_state_bucket"`

# kops create cluster --zones us-west-2a ${CLUSTER_NAME} -f kops-infra.yaml
kops create cluster --zones us-west-2a ${CLUSTER_NAME} --master-size=t2.micro --node-size=t2.micro \
                                                       --master-volume-size=8 --node-volume-size=8
kops update cluster ${CLUSTER_NAME} --yes
kubectl apply -f https://raw.githubusercontent.com/kubernetes/kops/master/addons/kubernetes-dashboard/v1.7.1.yaml
kubectl run --image=370535134506.dkr.ecr.us-west-2.amazonaws.com/samsara:latest demo3-samsara-app --port=9000 --replicas=2
kubectl expose deployment demo3-samsara-app --port=9000 --type=LoadBalancer
# kubectl proxy

aws s3 cp ~/.kube/config "${KOPS_STATE_STORE}/kube-config"
