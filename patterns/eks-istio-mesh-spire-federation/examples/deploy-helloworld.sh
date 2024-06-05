#/bin/bash

export CTX_CLUSTER1=foo-eks-cluster
export CTX_CLUSTER2=bar-eks-cluster


kubectl create --context="${CTX_CLUSTER1}" namespace sleep
kubectl create --context="${CTX_CLUSTER1}" namespace helloworld
kubectl create --context="${CTX_CLUSTER2}" namespace sleep
kubectl create --context="${CTX_CLUSTER2}" namespace helloworld

kubectl label --context="${CTX_CLUSTER1}" namespace sleep \
    istio-injection=enabled
kubectl label --context="${CTX_CLUSTER1}" namespace helloworld \
    istio-injection=enabled

kubectl label --context="${CTX_CLUSTER2}" namespace sleep \
    istio-injection=enabled
kubectl label --context="${CTX_CLUSTER2}" namespace helloworld \
    istio-injection=enabled

kubectl apply --context="${CTX_CLUSTER1}" \
    -f ./examples/helloworld-foo.yaml \
    -l service=helloworld -n helloworld
kubectl apply --context="${CTX_CLUSTER2}" \
    -f ./examples/helloworld-bar.yaml \
    -l service=helloworld -n helloworld

kubectl apply --context="${CTX_CLUSTER1}" \
    -f ./examples/helloworld-foo.yaml -n helloworld

kubectl -n helloworld --context="${CTX_CLUSTER1}" rollout status deploy helloworld-v1
kubectl -n helloworld get pod --context="${CTX_CLUSTER1}" -l app=helloworld

kubectl apply --context="${CTX_CLUSTER2}" \
    -f ./examples/helloworld-bar.yaml -n helloworld

kubectl -n helloworld  --context="${CTX_CLUSTER2}" rollout status deploy helloworld-v2
kubectl -n helloworld get pod --context="${CTX_CLUSTER2}" -l app=helloworld


kubectl apply --context="${CTX_CLUSTER1}" \
    -f ./examples/sleep-foo.yaml -n sleep
kubectl apply --context="${CTX_CLUSTER2}" \
    -f ./examples/sleep-bar.yaml -n sleep

kubectl -n sleep  --context="${CTX_CLUSTER1}" rollout status deploy sleep
kubectl -n sleep get pod --context="${CTX_CLUSTER1}" -l app=sleep

kubectl -n sleep  --context="${CTX_CLUSTER2}" rollout status deploy sleep
kubectl -n sleep get pod --context="${CTX_CLUSTER2}" -l app=sleep