# Istio single-network, multi-primary on EKS

In this setup the we would have a single VPC (single-network) in which we 
would create two EKS clusters. Istio would be installed on each of the EKS 
clusters as primary (multi-primary). 

The choice of IP addressing within each EKS
cluster is determined by the values of the `local` variables `eks_1_IPv6` and 
`eks_2_IPv6` which can be either `true` for `IPv6` and `false` for `IPv4`.

We have tested the all the following scenarios:
* EKS 1 (IPv4) and EKS 2 (IPv4)
* EKS 1 (IPv4) and EKS 2 (IPv6)
* EKS 1 (IPv6) and EKS 2 (IPv4)
* EKS 1 (IPv6) and EKS 2 (IPv6)

## Prerequisites

Ensure that you have installed the following tools locally:

1. [awscli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [istioctl](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl/)

## Choose the IP version for each EKS cluster

Edit the [`locals.tf`](locals.tf) and set the following variables either `true` 
if you want the specific EKS cluster to be `IPv6` or `false` for the specific EKS 
cluster to be based on `IPv4`
* `eks_1_IPv6` 
* `eks_2_IPv6` 

> **Note**: The above settings are independent of one another and need not be the 
> same

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

### Cross-Cluster Sync

Run the following commands to ensure that the public Load Balancer IP addresses 
are displayed in the output as shown. 

```sh 
./scripts/check-cross-cluster-sync.sh
```

> **Note:** If using different cluster names other than the default `eks-1` and 
`eks-2` use the following command:
```sh 
./scripts/check-cross-cluster-sync.sh eks_cluster_name_1 eks_cluster_name_2
```

The output should be similar to:
```
Updated context arn:aws:eks:us-west-2:XXXXXXXXXXXX:cluster/eks-1 in /Users/maverick/.kube/config
Updated context arn:aws:eks:us-west-2:XXXXXXXXXXXX:cluster/eks-2 in /Users/maverick/.kube/config

Cross cluster sync check for arn:aws:eks:us-west-2:XXXXXXXXXXXX:cluster/eks-1:
10.1.24.17:5000                                         HEALTHY     OK                outbound|5000||helloworld.sample.svc.cluster.local
44.227.39.238:15443                                     HEALTHY     OK                outbound|5000||helloworld.sample.svc.cluster.local
44.229.207.145:15443                                    HEALTHY     OK                outbound|5000||helloworld.sample.svc.cluster.local
52.33.147.49:15443                                      HEALTHY     OK                outbound|5000||helloworld.sample.svc.cluster.local

Cross cluster sync check for arn:aws:eks:us-west-2:XXXXXXXXXXXX:cluster/eks-2:
10.2.30.251:5000                                        HEALTHY     OK                outbound|5000||helloworld.sample.svc.cluster.local
34.213.174.24:15443                                     HEALTHY     OK                outbound|5000||helloworld.sample.svc.cluster.local
54.148.164.231:15443                                    HEALTHY     OK                outbound|5000||helloworld.sample.svc.cluster.local
54.148.184.188:15443                                    HEALTHY     OK                outbound|5000||helloworld.sample.svc.cluster.local
```

> **❗NOTE** If you don't see a clear output as show above, please see the 
> [Known Issues](#known-issues) and move ahead to the next step of testing the 
[Cross-cluster Load-Balancing](#cross-cluster-load-balancing) ignoring the 
outcome of this step. 

### Cross-cluster Load-Balancing 

Run the following command to check cross-cluster load balancing from the first 
cluster.

```
for i in {1..10}
do 
kubectl exec --context="${CTX_CLUSTER1}" -n sample -c sleep \
    "$(kubectl get pod --context="${CTX_CLUSTER1}" -n sample -l \
    app=sleep -o jsonpath='{.items[0].metadata.name}')" \
    -- curl -sS helloworld.sample:5000/hello
done
```
Also test similar command to check cross-cluster loadbalancing from the second 
cluster.

```
for i in {1..10}
do 
kubectl exec --context="${CTX_CLUSTER2}" -n sample -c sleep \
    "$(kubectl get pod --context="${CTX_CLUSTER2}" -n sample -l \
    app=sleep -o jsonpath='{.items[0].metadata.name}')" \
    -- curl -sS helloworld.sample:5000/hello
done
```

In either case the output should be similar to:

```
Hello version: v1, instance: helloworld-v1-867747c89-7vzwl
Hello version: v2, instance: helloworld-v2-7f46498c69-5g9rk
Hello version: v1, instance: helloworld-v1-867747c89-7vzwl
Hello version: v1, instance: helloworld-v1-867747c89-7vzwl
Hello version: v2, instance: helloworld-v2-7f46498c69-5g9rk
Hello version: v1, instance: helloworld-v1-867747c89-7vzwl
Hello version: v2, instance: helloworld-v2-7f46498c69-5g9rk
Hello version: v1, instance: helloworld-v1-867747c89-7vzwl
Hello version: v1, instance: helloworld-v1-867747c89-7vzwl
Hello version: v2, instance: helloworld-v2-7f46498c69-5g9rk
```

## Destroy 
```sh 
./scripts/destroy.sh 
```
## Known Issues

As of now because of how the Istio has been setup in EKS IPv6 clusters, the 
`istioctl` doesn't work well with IPv6 addresses. We are aware of it and would 
find a solutions for it in the next iteration.

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

## Documentation Links 

1. [Install Multi-Primary on different networks](https://istio.io/latest/docs/setup/install/multicluster/multi-primary_multi-network/)
2. [Verifying cross-cluster traffic](https://istio.io/latest/docs/setup/install/multicluster/verify/#verifying-cross-cluster-traffic)
3. [Multicluster Troubleshooting](https://istio.io/latest/docs/ops/diagnostic-tools/multicluster/)
