#!/bin/sh 

set -e

source `dirname "$(realpath $0)"`/set-cluster-contexts.sh $1 $2

for ctx in $CTX_CLUSTER1 $CTX_CLUSTER2
do 
    echo ">> Getting the root certificate for helloworld pod in $ctx cluster\n"
    POD_NAME=`kubectl --context "$ctx" get po -l app=helloworld -n sample -o json | jq -r ".items[0].metadata.name"`
    istioctl --context "$ctx" pc secret $POD_NAME -n sample -o json |\
        jq '[.dynamicActiveSecrets[] | select(.name == "ROOTCA")][0].secret.validationContext.trustedCa.inlineBytes' -r |\
        base64 -d
    echo "\n"
done
