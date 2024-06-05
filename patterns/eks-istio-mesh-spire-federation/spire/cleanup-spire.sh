#!/bin/bash


export CTX_CLUSTER1=foo-eks-cluster
export CTX_CLUSTER2=bar-eks-cluster

kubectl config use-context ${CTX_CLUSTER1}

kubectl delete CustomResourceDefinition spiffeids.spiffeid.spiffe.io
kubectl delete -n spire configmap k8s-workload-registrar
kubectl delete -n spire configmap trust-bundle
kubectl delete -n spire serviceaccount spire-agent
kubectl delete -n spire configmap spire-agent
kubectl delete -n spire daemonset spire-agent
kubectl delete csidriver csi.spiffe.io
kubectl delete -n spire configmap spire-server
kubectl delete -n spire serviceaccount spire-server
kubectl delete -n spire service spire-server
kubectl delete -n spire service spire-server-bundle-endpoint
kubectl delete -n spire statefulset spire-server
kubectl delete clusterrole k8s-workload-registrar-role spire-server-trust-role spire-agent-cluster-role
kubectl delete clusterrolebinding k8s-workload-registrar-role-binding spire-server-trust-role-binding spire-agent-cluster-role-binding
kubectl delete namespace spire

kubectl config use-context ${CTX_CLUSTER2}

kubectl delete CustomResourceDefinition spiffeids.spiffeid.spiffe.io
kubectl delete -n spire configmap k8s-workload-registrar
kubectl delete -n spire configmap trust-bundle
kubectl delete -n spire serviceaccount spire-agent
kubectl delete -n spire configmap spire-agent
kubectl delete -n spire daemonset spire-agent
kubectl delete csidriver csi.spiffe.io
kubectl delete -n spire configmap spire-server
kubectl delete -n spire serviceaccount spire-server
kubectl delete -n spire service spire-server
kubectl delete -n spire service spire-server-bundle-endpoint
kubectl delete -n spire statefulset spire-server
kubectl delete clusterrole k8s-workload-registrar-role spire-server-trust-role spire-agent-cluster-role
kubectl delete clusterrolebinding k8s-workload-registrar-role-binding spire-server-trust-role-binding spire-agent-cluster-role-binding
kubectl delete namespace spire