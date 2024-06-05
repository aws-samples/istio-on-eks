export CTX_CLUSTER1=foo-eks-cluster
export CTX_CLUSTER2=bar-eks-cluster

istioctl uninstall --purge --context $CTX_CLUSTER1 --skip-confirmation
istioctl uninstall --purge --context $CTX_CLUSTER2 --skip-confirmation