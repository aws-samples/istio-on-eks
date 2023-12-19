# Module 4 - Fault Injection

This module shows the fault injection capabilities of Istio service-mesh on Amazon EKS. 

## Prerequisites:
- [Module 1 - Getting Started](../01-getting-started/)

Note: This module will build on the application resources deployed in 
[Module 1 - Getting Started](../01-getting-started/). That means you **don't** have to execute the [Destroy](../01-getting-started/README.md#destroy) section in Module 1.

## Initial state setup

In this step we add the Istio mesh resources to wrap the `frontend`, `productcatalog` and
`catalogdetail` services.

A [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/) is created for [`catalogdetail`](./setup-mesh-resources/catalogdetail-destinationrule.yaml) to select subsets
based on the `version` label of the destination pods. However, the initial [`VirtualService`](./setup-mesh-resources/catalogdetail-virtualservice.yaml) definition does not specify any 
subset configuration thereby leading to a uniform traffic spread across both subsets.

### Deploy 

```bash
# Change directory to the right folder
cd ../04-fault-injection

# Apply virtual services & destination rule configuration
kubectl apply -f ./virtual-service-all.yaml
kubectl apply -f ./destination-rule-catalogdetail-v2.yaml 
```

Output should be similar to:
```bash
virtualservice.networking.istio.io/frontend configured
virtualservice.networking.istio.io/productcatalog configured
virtualservice.networking.istio.io/catalogdetail configured
destinationrule.networking.istio.io/catalogdetail configured
```

### Simulating Latency : HTTP Delay Fault Injection

Create a fault injection rule to delay traffic coming to catalogdetail service v1

```
kubectl apply -f virtual-service-catalogdetail-test-delay.yaml 
```

The contents of the file are as follows:

```
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: catalogdetail
spec:
  hosts:
  - catalogdetail
  http:
  - fault:
      delay:
        percentage:
          value: 100
        fixedDelay: 600s
    route:
    - destination:
        host: catalogdetail
        subset: v2
```

>The `fault` field in a VirtualService configuration is used to inject faults into the traffic that is routed to the service. The `delay` fault injects a delay into the traffic before it is forwarded to the service. The delay can be specified as a fixed amount of time or as a percentage of requests. The `percentage` value in the configuration provided indicates that the delay will be applied to 100% of requests to the `catalogdetail` service. The `fixedDelay` value of 600s indicates that the delay will be 600 seconds.

Expected Output:

```
virtualservice.networking.istio.io/catalogdetail configured
```

#### Validation

Confirm the rule was created : 

```
kubectl get virtualservice catalogdetail -o yaml
```

Allow few seconds for the new rule to propagate to all pods. Following which you should see the output something in line to below

```
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
...
spec:
  hosts:
  - catalogdetail
  http:
  - fault:
      delay:
        fixedDelay: 600s
        percentage:
          value: 100
    route:
    - destination:
        host: catalogdetail
        subset: v2
```

#### Verifying the delay configuration

* Open the Product Catalog web application in your browser.
* With the delay configuration in place, as illustrated below you should see the Catalog Detail toggling resulting in `Vendors: ABC.com, XYZ.com`. This is because the `catalogdetail` service has two versions `v1 (ABC.com)` and `v2(ABC.com, XYZ.com)` and the delay in `catalogdetail-v1` has resulted in routing the requests to `catalogdetail-v2` 

![Application Snapshot](../../images/04-fault-injection-app-snapshot.png)

### Interrupting Requests : HTTP Abort Fault Injection

Another way to test microservice resiliency is to introduce an HTTP abort fault. In this task, we will introduce an HTTP abort to the `catalogdetail` microservices

Create a fault injection rule to send an HTTP abort

```
kubectl apply -f virtual-service-catalogdetail-test-abort.yaml
```

Expected Output: 

```
virtualservice.networking.istio.io/catalogdetail configured
```

Confirm the rule was created

```
kubectl get virtualservice catalogdetail -o yaml
```

Expected Output: 

```
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
...
spec:
  hosts:
  - catalogdetail
  http:
  - fault:
      abort:
        httpStatus: 500
        percentage:
          value: 100
    route:
    - destination:
        host: catalogdetail
        subset: v2
```

>The `fault` field in a VirtualService configuration is used to inject faults into the traffic that is routed to the service. The `abort` fault injects an abort into the traffic before it is forwarded to the service. The `percentage` value in the configuration provided indicates that the abort will be applied to 100% of requests to the `catalogdetail` service. The `httpStatus` value of 500 indicates that the client will receive a 500 Internal Server Error response. However, the route section directs the traffic to the v2 subset of the catalogdetail service, regardless of whether the abort occurred or not. This means that even though an abort is injected, the request will still be sent to the v2 subset.

#### Verifying the abort configuration

* Open the Product Catalog web application in your browser.
* With the abort configuration in place, as illustrated below you should see the Catalog Detail toggling resulting in `Vendors: ABC.com, XYZ.com`. This is because the `catalogdetail` service has two versions `v1 (ABC.com)` and `v2(ABC.com, XYZ.com.)` and the abort in in `catalogdetail-v1` has resulted in routing the requests to `catalogdetail-v2`

![Application Snapshot](../../images/04-fault-injection-app-snapshot.png)

## Cleanup 

### Remove the application routing rules
```bash
kubectl delete -f virtual-service-all.yaml 
```

Refer to [Destroy](../01-getting-started/README.md#destroy) section for 
cleanup of application resources.
