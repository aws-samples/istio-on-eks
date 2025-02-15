# Istio Multi-Primary on Single Network 

This repository demonstrates how to deploy Istio in a multi-primary configuration on Amazon EKS using a single VPC. It showcases Istio's capability to manage service meshes across different clusters while maintaining a single network environment.

## Overview

In this setup, we deploy two Amazon EKS clusters (IPv4 and IPv6) in a single VPC, configuring them with Istio in a Multi-Primary setup. The Istio will be set-up to operate in a [Multi-Primary](https://istio.io/latest/docs/setup/install/multicluster/multi-primary/) way where services are shared across clusters.

* Deploy a VPC with additional security groups to allow cross-cluster communication and communication from nodes to the other cluster API Server endpoint
* Deploy 2 EKS Cluster with one managed node group in an VPC
* Add node_security_group rules for port access required for Istio communication
* Install Istio using Helm resources in Terraform
* Install Istio Ingress Gateway using Helm resources in Terraform
* Deploy/Validate Istio communication using sample application

Refer to the [documentation](https://istio.io/latest/docs/concepts/) for `Istio` concepts.


## Folder structure
### Folder [`0.certs-tool`](0.certs-tool/)

This folder is the [Makefiles](https://github.com/istio/istio/tree/master/tools/certs) from the Istio projects to generate 1 root CA with 2 intermediate CAs for each cluster. Please refer to the ["Certificate Management"](https://istio.io/latest/docs/tasks/security/cert-management/) section in the Istio documentation. For production setup it's [highly recommended](https://istio.io/latest/docs/tasks/security/cert-management/plugin-ca-cert/#plug-in-certificates-and-key-into-the-cluster) by the Istio project to have a production-ready CA solution.

> **_NOTE:_**  The [0.certs-tool/create-certs.sh](0.certs-tool/create-certs.sh) script needs to run before the cluster creation so the code will pick up the relevant certificates

### Folder [`0.vpc`](0.vpc/)

This folder creates the VPC for both clusters. The VPC is enabled for dual-stack, supporting both IPv4 and IPv6 addressing. The VPC creation is not part of the cluster provisioning and therefore lives in a separate folder.
To support the multi-cluster/Multi-Primary setup, this folder also creates additional security groups to be used by each cluster's worker nodes to allow cross-cluster communication (resources `cluster1_additional_sg` and `cluster2_additional_sg`). These security groups allow communication from one to the other and each will be added to the worker nodes of the relevant cluster.

### Folder [`1.cluster1`](1.cluster1/)

This folder creates an Amazon EKS Cluster, named by default `cluster-1` (see [`variables.tf`](1.cluster1/variables.tf)), configured to use IPv4 addressing. It also includes AWS Load Balancer Controller and Istio installation.
Configurations in this folder to be aware of:
* The cluster is configured to use the security groups created in the `0.vpc` folder (`cluster1_additional_sg` in this case).
* Kubernetes Secret named `cacerts` is created with the certificates created by the [0.certs-tool/create-certs.sh](0.certs-tool/create-certs.sh) script
* Kubernetes Secret named `istio-reader-service-account-istio-remote-secret-token` of type `Service-Account` is being created. This is to replicate the [istioctl experimental create-remote-secret](https://istio.io/latest/docs/reference/commands/istioctl/#istioctl-experimental-create-remote-secret) command. This secret will be used in folder [`3.istio-multi-primary`](3.istio-multi-primary/) to apply kubeconfig secret with tokens from the other cluster to be able to communicate to the other cluster API Server

### Folder [`2.cluster2`](2.cluster2/)

This folder creates the second Amazon EKS Cluster, named by default `cluster-2`, configured to use IPv6 addressing. The rest of the configuration is similar to `1.cluster1`, including AWS Load Balancer Controller and Istio installation.


### Folder [`3.istio-multi-primary`](3.istio-multi-primary/)

This folder deploys a reader secret on each cluster. It replicates the [`istioctl experimental create-remote-secret`](https://istio.io/latest/docs/reference/commands/istioctl/#istioctl-experimental-create-remote-secret) by applying a kubeconfig secret prefixed `istio-remote-secret-` with the cluster name at the end.


## Prerequisites:

Ensure that you have the following tools installed locally:

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [istioctl](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl/)

## Deploy

### Prereq - Provision Certificates

```shell
cd 0.certs-tool
./create-certs.sh
cd..
```

### Step 0 - Create the VPC

```shell
cd 0.vpc
terraform init
terraform apply -auto-approve
cd..
```

### Step 1 - Deploy cluster-1

```shell
cd 1.cluster1
terraform init
terraform apply -auto-approve
cd..
```

### Step 2 - Deploy cluster-2

```shell
cd 2.cluster2
terraform init
terraform apply -auto-approve
cd..
```

### Step 3 - Configure Istio Multi-Primary

```shell
cd 3.istio-multi-primary
terraform init
terraform apply -auto-approve
cd..
```
## Validation and Testing

* Validate the deployed components
    * Set the context for both clusters using the following commands: 
        ```shell
        export CLUSTER_1=cluster-1
        export CLUSTER_2=cluster-2
        export AWS_DEFAULT_REGION=$(aws configure get region)
        export AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --query "Account" --output text)
        
        aws eks update-kubeconfig --name $CLUSTER_1 --region $AWS_DEFAULT_REGION
        aws eks update-kubeconfig --name $CLUSTER_2 --region $AWS_DEFAULT_REGION
        
        export CTX_CLUSTER_1=arn:aws:eks:$AWS_DEFAULT_REGION:${AWS_ACCOUNT_NUMBER}:cluster/$CLUSTER_1
        export CTX_CLUSTER_2=arn:aws:eks:$AWS_DEFAULT_REGION:${AWS_ACCOUNT_NUMBER}:cluster/$CLUSTER_2
        ```
    * Check the worker nodes on each cluster using the following command: 
        ```shell
        kubectl get nodes -o wide --context=$CTX_CLUSTER_1
        
        kubectl get nodes -o wide --context=$CTX_CLUSTER_2
        ```
    * Check Istio components running on the istio-system namespace
        ```shell
        kubectl get pods,svc -n istio-system --context=$CTX_CLUSTER_1
        
        kubectl get pods,svc -n istio-system --context=$CTX_CLUSTER_2
        ```
    * Set the flags to enable PODs in an IPv4 cluster support IPv6 egress and vice versa
        
        Run this command to set ENABLE_V6_EGRESS flag on Cluster-1: 
        ```shell
        kubectl patch daemonset aws-node -n kube-system -p '{"spec": {"template": {"spec": {"initContainers": [{"env":[{"name":"ENABLE_V6_EGRESS","value":"true"}],"name":"aws-vpc-cni-init"}]}}}}' --context=$CTX_CLUSTER_1
        ```
        
        Run this command to set ENABLE_V4_EGRESS flag on Cluster-2:
        ```shell
        kubectl patch daemonset aws-node -n kube-system -p '{"spec": {"template": {"spec": {"initContainers": [{"env":[{"name":"ENABLE_V4_EGRESS","value":"true"}],"name":"aws-vpc-cni-init"}]}}}}' --context=$CTX_CLUSTER_2
        ```

* Test cross cluster communication
    
    To verify the multi-cluster setup, follow the steps outlined in the official Istio documentation: https://istio.io/latest/docs/setup/install/multicluster/verify/
    * This guide walks you through deploying sample applications on both clusters and testing cross-cluster communication using curl commands. 
    * Review the deployed sample apps using the commands below:
        
        ```shell
        kubectl get pods,svc -n sample --context=$CTX_CLUSTER_1
        
        kubectl get pods,svc -n sample --context=$CTX_CLUSTER_2
        ```
    * Now that the sample apps are deployed, run the following command from each cluster to test the cross cluster communication
        
        From Cluster-1: 
        ```shell
        for i in {1..10}
        do
        kubectl exec --context="${CTX_CLUSTER_1}" -n sample -c curl \
        "$(kubectl get pod --context="${CTX_CLUSTER_1}" -n sample -l \
        app=curl -o jsonpath='{.items[0].metadata.name}')" \
        -- curl -sS helloworld.sample:5000/hello
        done
        ```
        
        From Cluster-2:
        ```shell
        for i in {1..10}
        do
        kubectl exec --context="${CTX_CLUSTER_2}" -n sample -c sleep \
        "$(kubectl get pod --context="${CTX_CLUSTER_2}" -n sample -l \
        app=curl -o jsonpath='{.items[0].metadata.name}')" \
        -- curl -sS helloworld.sample:5000/hello
        done
        ```
        
        Output: 
        Verify in the response the HelloWorld version should toggle between v1 and v2


## Destroy

To teardown and remove the resources created in this example:

```shell
cd 3.istio-multi-primary
terraform apply -destroy -autoapprove
cd ../2.cluster2
terraform apply -destroy -autoapprove
cd ../1.cluster1
terraform apply -destroy -autoapprove
cd ../0.vpc
terraform apply -destroy -autoapprove
```
