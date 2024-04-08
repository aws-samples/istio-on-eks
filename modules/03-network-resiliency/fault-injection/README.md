# Network Resiliency - Fault Injection

This sub-module focuses on Istio service-mesh features like **Delay and Abort** for network resiliency on Amazon EKS. 

1. [Delay](#injecting-delay-fault-into-http-requests)
2. [Abort](#injecting-abort-fault-into-http-requests)

## Injecting Delay Fault into HTTP Requests

In this step we setup the delay configuration for `catalogdetail` virtual service

### Deploy

```sh
# This assumes that you are currently in "istio-on-eks/modules/03-network-resiliency/fault-injection" directory

kubectl apply -f ./delay/catalogdetail-virtualservice.yaml
```

Output should be similar to:
```sh
virtualservice.networking.istio.io/catalogdetail configured
```

### Validate

Run the following command to retrieve the YAML configuration for [`catalogdetail`](./delay/catalogdetail-virtualservice.yaml) `VirtualService`.

```sh
kubectl get virtualservice catalogdetail -o yaml -n workshop
```

Output should be similar to:
```sh
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"networking.istio.io/v1alpha3","kind":"VirtualService","metadata":{"annotations":{},"name":"catalogdetail","namespace":"workshop"},"spec":{"hosts":["catalogdetail"],"http":[{"fault":{"delay":{"fixedDelay":"15s","percentage":{"value":100}}},"match":[{"headers":{"user":{"exact":"internal"}}}],"route":[{"destination":{"host":"catalogdetail","port":{"number":3000}}}]},{"route":[{"destination":{"host":"catalogdetail","port":{"number":3000}}}]}]}}
  creationTimestamp: "2024-01-19T17:47:48Z"
  generation: 12
  name: catalogdetail
  namespace: workshop
  resourceVersion: "35171847"
  uid: 2060b9cd-1e4b-4127-bf94-5c6bc679f286
spec:
  hosts:
  - catalogdetail
  http:
  - fault:
      delay:
        fixedDelay: 15s
        percentage:
          value: 100
    match:
    - headers:
        user:
          exact: internal
    route:
    - destination:
        host: catalogdetail
        port:
          number: 3000
  - route:
    - destination:
        host: catalogdetail
        port:
          number: 3000
```

### Test

Test the delay by running a `curl` command against the `catalogdetail` for user named 'internal' and 'external'.

```sh  
# Set the FE_POD_NAME variable to the name of the frontend pod in the workshop namespace

export FE_POD_NAME=$(kubectl get pods -n workshop -l app=frontend -o jsonpath='{.items[].metadata.name}')
```

```sh  
# Access the frontend container in the workshop namespace interactively

kubectl exec -it ${FE_POD_NAME} -n workshop -c frontend -- bash
```

Output should be similar to:
```sh  
root@frontend-container-id:/app#

# Allows accessing the shell inside the frontend container for executing commands
```

Run the `curl` command for the user named 'internal'
```sh 
curl http://catalogdetail:3000/catalogdetail/ -s -H "user: internal" -o /dev/null \
-w "Time taken to start transfer: %{time_starttransfer}\n"
```

Output should be similar to:
```sh
Time taken to start transfer: 15.009529

# A 15-sec delay is introduced for user named 'internal' based on the delay fault configuration for 'catalogdetail' virtual service
```

Run the `curl` command for the user named 'external' (could be any user other than 'internal')
```sh 
curl http://catalogdetail:3000/catalogdetail/ -s -H "user: external" -o /dev/null \
-w "Time taken to start transfer: %{time_starttransfer}\n"
```

Output should be similar to:
```sh
Time taken to start transfer: 0.006548

# No delay is introduced for user named 'external', since delay fault configuration in 'catalogdetail' virtual service was only applied for user named 'internal'
```

Exit from the shell inside the frontend container

```sh
root@frontend-container-id:/app#exit
```

## Injecting Abort Fault into HTTP Requests

In this step we setup the abort configuration for `catalogdetail` virtual service

### Deploy

```sh
# This assumes that you are currently in "istio-on-eks/modules/03-network-resiliency/fault-injection" directory

kubectl apply -f ./abort/catalogdetail-virtualservice.yaml
```

Output should be similar to:
```sh
virtualservice.networking.istio.io/catalogdetail configured
```

### Validate

Run the following command to retrieve the YAML configuration for [`catalogdetail`](./abort/catalogdetail-virtualservice.yaml) `VirtualService`.

```sh
kubectl get virtualservice catalogdetail -o yaml -n workshop
```

Output should be similar to:
```sh
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"networking.istio.io/v1alpha3","kind":"VirtualService","metadata":{"annotations":{},"name":"catalogdetail","namespace":"workshop"},"spec":{"hosts":["catalogdetail"],"http":[{"fault":{"abort":{"httpStatus":500,"percentage":{"value":100}}},"match":[{"headers":{"user":{"exact":"internal"}}}],"route":[{"destination":{"host":"catalogdetail","port":{"number":3000}}}]},{"route":[{"destination":{"host":"catalogdetail","port":{"number":3000}}}]}]}}
  creationTimestamp: "2024-01-19T17:47:48Z"
  generation: 13
  name: catalogdetail
  namespace: workshop
  resourceVersion: "35180991"
  uid: 2060b9cd-1e4b-4127-bf94-5c6bc679f286
spec:
  hosts:
  - catalogdetail
  http:
  - fault:
      abort:
        httpStatus: 500
        percentage:
          value: 100
    match:
    - headers:
        user:
          exact: internal
    route:
    - destination:
        host: catalogdetail
        port:
          number: 3000
  - route:
    - destination:
        host: catalogdetail
        port:
          number: 3000
```

### Test

Test the abort by running a `curl` command against the `catalogdetail` for user named 'internal' and 'external'.

```sh  
# Access the frontend container in the workshop namespace interactively

kubectl exec -it ${FE_POD_NAME} -n workshop -c frontend -- bash
```

Output should be similar to:
```sh  
root@frontend-container-id:/app#

# Allows accessing the shell inside the frontend container for executing commands
```


Run the `curl` command for the user named 'internal'
```sh 
curl http://catalogdetail:3000/catalogdetail/ -s -H "user: internal" -o /dev/null \
-w "HTTP Response: %{http_code}\n"
```

Output should be similar to:
```sh
HTTP Response: 500

# HTTP code 500 (Abort) is returned for user named 'internal' based on the abort fault configuration for 'catalogdetail' virtual service
```

Run the `curl` command for the user named 'external' (could be any user other than 'internal') 
```sh 
curl http://catalogdetail:3000/catalogdetail/ -s -H "user: external" -o /dev/null \
-w "HTTP Response: %{http_code}\n"
```

Output should be similar to:
```sh
HTTP Response: 200

# HTTP code 200 (Success) is returned for user named 'external', since abort fault configuration in 'catalogdetail' virtual service was only applied for user named 'internal'
```
Exit from the shell inside the frontend container

```sh
root@frontend-container-id:/app#exit
```

### Reset the environment

Run the same set of steps as in the [Initial state setup](../README.md#initial-state-setup) to reset the environment.