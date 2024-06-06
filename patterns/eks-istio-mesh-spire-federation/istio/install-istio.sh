#/bin/bash

set -e


export CTX_CLUSTER1=foo-eks-cluster
export CTX_CLUSTER2=bar-eks-cluster

eks_api_foo="$1"
eks_api_bar="$2"

istioctl install -f ./istio/foo-istio-conf.yaml --context="${CTX_CLUSTER1}" --skip-confirmation
kubectl apply -f ./istio/auth.yaml --context="${CTX_CLUSTER1}"
kubectl apply -f ./istio/istio-ew-gw.yaml --context="${CTX_CLUSTER1}"

istioctl install -f ./istio/bar-istio-conf.yaml --context="${CTX_CLUSTER2}" --skip-confirmation
kubectl apply -f ./istio/auth.yaml --context="${CTX_CLUSTER2}"
kubectl apply -f ./istio/istio-ew-gw.yaml --context="${CTX_CLUSTER2}"


istioctl x create-remote-secret --context="${CTX_CLUSTER1}" --name=foo-eks-cluster \
  --server="${eks_api_foo}" \
  | kubectl apply -f - --context="${CTX_CLUSTER2}"

istioctl x create-remote-secret --context="${CTX_CLUSTER2}" --name=bar-eks-cluster \
  --server="${eks_api_bar}" \
  | kubectl apply -f - --context="${CTX_CLUSTER1}"
