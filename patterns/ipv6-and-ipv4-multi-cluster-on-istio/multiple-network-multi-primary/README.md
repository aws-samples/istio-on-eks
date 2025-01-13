# Istio multi-network, multi-primary on EKS

This repository demonstrates how to deploy Istio in a multi-network, multi-primary configuration on Amazon EKS. It showcases Istio's capability to manage service meshes across different network environments, ideal for multi-cloud or hybrid cloud scenarios. The setup includes:

* Two separate Amazon VPCs:
  * VPC 1 (network1) for Cluster-1
  * VPC 2 (network2) for Cluster-2
   
* Two Amazon EKS clusters with different IP protocols:
  * Cluster-1: Primary cluster in network1, using IPv4
  * Cluster-2: Primary cluster in network2, using IPv6
  

![Istio Multi-Cluster Architecture](istio-multi-cluster-architecture.png "Istio Multi-Cluster Architecture on Amazon EKS")

## Prerequisites

Ensure that you have installed the following tools locally:

1. [awscli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [istioctl](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl/)

## Deploy 

To deploy the terraform repo, run the commands shown below:
```sh 
./scripts/deploy.sh 
```

After running the command successfully, set the kubeconfig for both EKS clusters:
```sh 
source scripts/set-cluster-contexts.sh
```

> **Note:** If using different cluster names other than the default `eks-1` and 
`eks-2`, use the following command:

```sh 
source scripts/set-cluster-contexts.sh eks_cluster_name_1 eks_cluster_name_2
```


## Testing


Run the following command to check cross-cluster loadbalancing from the first 
cluster.

```
for i in {1..10}
do
kubectl exec --context="${CTX_CLUSTER_1}" -n sample -c curl \
"$(kubectl get pod --context="${CTX_CLUSTER_1}" -n sample -l \
app=curl -o jsonpath='{.items[0].metadata.name}')" \
-- curl -sS helloworld.sample:5000/hello
done
```
Also test similar command to check cross-cluster loadbalancing from the second 
cluster.

```
for i in {1..10}
do
kubectl exec --context="${CTX_CLUSTER_2}" -n sample -c curl \
"$(kubectl get pod --context="${CTX_CLUSTER_2}" -n sample -l \
app=curl -o jsonpath='{.items[0].metadata.name}')" \
-- curl -sS helloworld.sample:5000/hello
done
```

Verify that the responses for both above commands return HelloWorld version toggling between v1 and v2 

## Destroy 
```sh 
./scripts/destroy.sh 
```

## Troubleshooting

There are many things that can go wrong when deploying a complex solutions such 
as this, Istio multi-primary on different networks.

### Ordering in Terraform deployment

The ordering is important when deploying the resources with Terraform and here 
it is:
1. Deploy the VPCs and EKS clusters 
2. Deploy the `cacerts` secret in the `istio-system` namespace in both clusters
4. Deploy the control plane `istiod` in both clusters
5. Deploy the rest of the resources, including Helm Chart `multicluster-gateway-n-apps`
in both clusters. 

The `multicluster-gateway-n-apps` Helm chart includes the following key resources:
1. `Deployment`, `Service Account` and `Service` definitions for `sleep` app
2. `Deployment` and `Service` definitions for `helloworld` app
3. Static `Gateway` definition of `cross-network-gateway` in `istio-ingress` namespace 
4. Templated `Secret` definition of `istio-remote-secret-*`





