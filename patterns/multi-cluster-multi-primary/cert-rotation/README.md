# Root CA Certificate Rotation - Istio on EKS

This folder can be used to rotate the Root CA certificates on single cluster
or Multi-cluster Istio Service Mesh.

## Prerequisites 

The following tools must be installed or available for use:
1. Ansible v2.18.6
2. Python v3.13.5

> **Note:** This certificate rotation utility assumes you are using the EKS clusters
> provided by the modules in the parent folder

## Certificate Rotation on Single Cluster Mesh

Edit the file [host_vars/localhost](host_vars/localhost) and update the entry 
with the key `eks_ctx` by replacing `XXXXXXXXXXXX` with your AWS account number.

Run the provided Ansible playbook by running the command:

```sh
ansible-playbook single-cluster.yaml 
```

## Certificate Rotation on Multi-Cluster Mesh 

Edit the file [host_vars/localhost](host_vars/localhost) and update the entry 
with the key `eks_1_ctx` and `eks_2_ctx` by replacing `XXXXXXXXXXXX` with your 
AWS account number.

Run the provided Ansible playbook by running the command:

```sh
ansible-playbook multi-cluster.yaml 
```

### Verification

You can use the script [scripts/check-workload-certificate.sh](scripts/check-workload-certificate.sh)
before and after the certificate rotation to verify if the certificates have
been picked up.
