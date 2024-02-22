# Network Resiliency 

This module will cover the network resiliency capabilities of Istio service-mesh on Amazon EKS. 


## Prerequisites:
1. [Module 1 - Getting Started](../01-getting-started/)
2. [Install `istioctl` and add it to the $PATH](https://istio.io/latest/docs/ops/diagnostic-tools/istioctl/#install-hahahugoshortcode860s2hbhb)

>Note: This module will build on the application resources deployed in 
[Module 1 - Getting Started](../01-getting-started/). That means you **don't** have to execute the [Destroy](../01-getting-started/README.md#destroy) section in Module 1.

## Initial state setup
  
In this step we add the Istio mesh resources to wrap the `frontend`, `productcatalog` and
`catalogdetail` services.

A [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/) is created for [`catalogdetail`](../../00-setup-mesh-resources/catalogdetail-destinationrule.yaml) to select subsets
based on the `version` label of the destination pods. However, the initial [`VirtualService`](../../00-setup-mesh-resources/catalogdetail-virtualservice.yaml) definition does not specify any 
subset configuration thereby leading to a uniform traffic spread across both subsets.

```bash
# This assumes that you are currently in "istio-on-eks/modules/01-getting-started" folder
cd ../03-network-resiliency

# Install the mesh resources
kubectl apply -f ../00-setup-mesh-resources/
```

Output should be similar to:

```
destinationrule.networking.istio.io/catalogdetail created
virtualservice.networking.istio.io/catalogdetail created
virtualservice.networking.istio.io/frontend created
virtualservice.networking.istio.io/productcatalog created
```

## 🧱 Sub Modules of Network Resiliency

### [1. Fault Injection](fault-injection/README.md)
### [2. Timeout, Retries and Circuit Breaking](timeouts-retries-circuitbreaking/README.md)
### [3. Rate Limiting](rate-limiting/README.md)








