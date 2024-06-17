#/bin/bash

set -e

export CTX_CLUSTER1=foo-eks-cluster
export CTX_CLUSTER2=bar-eks-cluster

spire_server_node_foo=$(kubectl get nodes -l dedicated=spire-server --context="${CTX_CLUSTER1}" -o jsonpath='{.items[*].metadata.name}')
spire_server_node_bar=$(kubectl get nodes -l dedicated=spire-server --context="${CTX_CLUSTER2}" -o jsonpath='{.items[*].metadata.name}')

# Install Spire on foo cluster
kubectl apply -f ./spire/configmaps.yaml --context="${CTX_CLUSTER1}"
cat ./spire/foo-spire.yaml | sed "s/<spire_server_node_bar>/$spire_server_node_bar/g" | kubectl apply -f - --context="${CTX_CLUSTER1}"

kubectl -n spire rollout status statefulset spire-server --context="${CTX_CLUSTER1}"
kubectl -n spire rollout status daemonset spire-agent --context="${CTX_CLUSTER1}"

foo_bundle=$(kubectl exec --context="${CTX_CLUSTER1}" -c spire-server -n spire --stdin spire-server-0  -- /opt/spire/bin/spire-server bundle show -format spiffe -socketPath /run/spire/sockets/server.sock)

# Install Spire on bar cluster
kubectl apply -f ./spire/configmaps.yaml --context="${CTX_CLUSTER2}"
cat ./spire/bar-spire.yaml | sed "s/<spire_server_node_foo>/$spire_server_node_foo/g" | kubectl apply -f - --context="${CTX_CLUSTER2}"

kubectl -n spire rollout status statefulset spire-server --context="${CTX_CLUSTER2}"
kubectl -n spire rollout status daemonset spire-agent --context="${CTX_CLUSTER2}"

bar_bundle=$(kubectl exec --context="${CTX_CLUSTER2}" -c spire-server -n spire --stdin spire-server-0 -- /opt/spire/bin/spire-server bundle show -format spiffe -socketPath /run/spire/sockets/server.sock)

# Set foo.com bundle to bar.com SPIRE bundle endpoint
kubectl exec --context="${CTX_CLUSTER2}" -c spire-server -n spire --stdin spire-server-0 \
  -- /opt/spire/bin/spire-server bundle set -format spiffe -id spiffe://foo.com -socketPath /run/spire/sockets/server.sock <<< "$foo_bundle"

# Set bar.com bundle to foo.com SPIRE bundle endpoint
kubectl exec --context="${CTX_CLUSTER1}" -c spire-server -n spire --stdin spire-server-0 \
  -- /opt/spire/bin/spire-server bundle set -format spiffe -id spiffe://bar.com -socketPath /run/spire/sockets/server.sock <<< "$bar_bundle"