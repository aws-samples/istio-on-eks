# Module 4 - Security

This module will cover security related capabilities of Istio service-mesh on Amazon EKS.

## Prerequisites:

  - [Module 1 - Getting Started](../01-getting-started/)

**Note:** This module will build on the application resources deployed in 
[Module 1 - Getting Started](../01-getting-started/). That means you **don't** have to execute the [Destroy](../01-getting-started/README.md#destroy) section in Module 1.

## Initial state setup

**Note::** Ensure [Prerequisites](#prerequisites) are met before proceeding.

In this step we add the Istio mesh resources to wrap the `frontend`, `productcatalog` and
`catalogdetail` services.

A [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/) is created for [`catalogdetail`](../00-setup-mesh-resources/catalogdetail-destinationrule.yaml) to select subsets
based on the `version` label of the destination pods. However, the initial [`VirtualService`](../00-setup-mesh-resources/catalogdetail-virtualservice.yaml) definition does not specify any 
subset configuration thereby leading to a uniform traffic spread across both subsets.

### Deploy 

Change to the security module sub-directory before proceeding further.

```bash
# This assumes that you are currently inside one of the other module sub-directories
# like "istio-on-eks/modules/xx-xxxxx".
# Adjust the directory path based on your current directory location.
cd ../04-security

# Install the mesh resources
kubectl apply -f ../00-setup-mesh-resources/
```

Output should be similar to:
```bash
destinationrule.networking.istio.io/catalogdetail created
virtualservice.networking.istio.io/catalogdetail created
virtualservice.networking.istio.io/frontend created
virtualservice.networking.istio.io/productcatalog created
```

### Validate

#### Istio Resources

Run the following command to list all the Istio resources created.

```bash
kubectl get Gateway,VirtualService,DestinationRule -n workshop
```

Output should be similar to:
```bash
NAME                                             AGE
gateway.networking.istio.io/productapp-gateway   25m

NAME                                                GATEWAYS                 HOSTS                AGE
virtualservice.networking.istio.io/catalogdetail                             ["catalogdetail"]    48s
virtualservice.networking.istio.io/frontend                                  ["frontend"]         48s
virtualservice.networking.istio.io/productapp       ["productapp-gateway"]   ["*"]                25m
virtualservice.networking.istio.io/productcatalog                            ["productcatalog"]   48s

NAME                                                HOST                                       AGE
destinationrule.networking.istio.io/catalogdetail   catalogdetail.workshop.svc.cluster.local   48s
```

## 🧱 Sub Modules of Security

### 1. Peer Authentication - *TBD*
### [2. Request Authentication](request-authentication/README.md)
### [3. OPA External Authorization](opa-external-authorization/README.md)