# Network Resiliency -  Rate Limiting
This sub-module will cover the Istio service-mesh feature of rate limiting for network resiliency on Amazon EKS.

Use the following links to quickly jump to the desired section:
1. [Local Rate Limiting](#local-rate-limiting)
2. [Global Rate Limiting](#global-rate-limiting)
3. [Reset the environment](#reset-the-environment)

## Local Rate Limiting

Apply Local Rate Limiting to the `productcatalog` Service

```sh
kubectl apply -f local-ratelimit/local-ratelimit.yaml
```

Looking into the contents of the file [local-ratelimit.yaml](local-ratelimit/local-ratelimit.yaml)

1. The **HTTP_FILTER** patch inserts the `envoy.filters.http.local_ratelimit` [local envoy filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/local_rate_limit_filter#config-http-filters-local-rate-limit) into the HTTP connection manager filter chain. 
2. The local rate limit filter’s [token bucket](https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/filters/http/local_ratelimit/v3/local_rate_limit.proto#envoy-v3-api-field-extensions-filters-http-local-ratelimit-v3-localratelimit-token-bucket) is configured to allow **10 requests/min**. 
3. The filter is also configured to add an `x-local-rate-limit` response header to requests that are blocked.

### Test

To test the rate limiter in action, exec into a pod in the mesh, in our example below it is the `frontend` pod and send a bunch of requests to the `prodcatalog` service to trigger the rate limiter. 

```sh
POD_NAME=$(kubectl get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}' -n workshop)

kubectl exec $POD_NAME -n workshop -c frontend -- \
bash -c "for i in {1..20}; do curl -sI http://productcatalog:5000/products/; done" 
```

Since the 20 requests are sent in less than a minute, after the first 10 requests are accepted by the service you’ll start seeing **HTTP 429** response codes from the service.

Successful requests will return the following output:

```
HTTP/1.1 200 OK
content-type: application/json
content-length: 124
x-amzn-trace-id: Root=1-6502273f-8dd970ab66ed073ccd2519c7
access-control-allow-origin: *
server: envoy
date: Wed, 13 Sep 2023 21:18:55 GMT
x-envoy-upstream-service-time: 15
x-ratelimit-limit: 10
x-ratelimit-remaining: 9
x-ratelimit-reset: 45
```

While requests that are rate limited will return the following output:

```
HTTP/1.1 429 Too Many Requests
x-local-rate-limit: true
content-length: 18
content-type: text/plain
x-ratelimit-limit: 10
x-ratelimit-remaining: 0
x-ratelimit-reset: 45
date: Wed, 13 Sep 2023 21:18:55 GMT
server: envoy
x-envoy-upstream-service-time: 0
```

Similarly, if you run the same command without `-I` flag, you will see the 
responses as shown below: 

For successful requests:

```
{
    "products": {},
    "details": {
        "version": "2",
        "vendors": [
            "ABC.com, XYZ.com"
        ]
    }
}  
```
And for rate-limited requests:

```
local_rate_limited
```

## Global Rate Limiting

### Setup Global Rate Limiting service

To be able to use the Global Rate Limit in our Istio service-mesh we need a global 
rate limit service that implements Envoy’s rate limit service protocol. 

1. Configuration for the Global Rate Limit service
   * Configuration is captured in `ratelimit-config` **ConfigMap** in the file 
   [global-ratelimit-config.yaml](global-ratelimit/global-ratelimit-config.yaml)
   * As can be observed in the file, rate limit requests to the `/` path is set to
    **5 requests/minute** and all other requests at **100 requests/minute**.
2. Global Rate Limit service with Redis
   *  File [global-ratelimit-service.yaml](global-ratelimit/global-ratelimit-service.yaml) 
   has **Deployment** and **Service** definitions for 
      * Central Rate Limit Service
      * Redis
   

Apply the Global Rate Limiting configuration and deploy the dependent services 
as shown below to the EKS cluster and Istio service-mesh.

```sh
kubectl apply -f global-ratelimit/global-ratelimit-config.yaml
kubectl apply -f global-ratelimit/global-ratelimit-service.yaml
```

### Apply the Global Rate Limits

Applying global rate limits is done in two steps:

1. Apply an EnvoyFilter to the ingressgateway to enable global rate limiting 
using Envoy’s global rate limit filter.

   ```sh
   kubectl apply -f global-ratelimit/filter-ratelimit.yaml
   ```
   Looking at the file [filter-ratelimit.yaml](global-ratelimit/filter-ratelimit.yaml)
   * The  configuration inserts the `envoy.filters.http.ratelimit` [global envoy filter](https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/filters/http/ratelimit/v3/rate_limit.proto#envoy-v3-api-msg-extensions-filters-http-ratelimit-v3-ratelimit) into the **HTTP_FILTER** chain.
   * The `rate_limit_service` field specifies the external rate limit service, `outbound|8081||ratelimit.workshop.svc.cluster.local` in this case.

2. Apply another EnvoyFilter to the ingressgateway that defines the route configuration on which to rate limit. 

   Looking at the file [filter-ratelimit-svc.yaml](global-ratelimit/filter-ratelimit-svc.yaml)
   * The configuration adds rate limit actions for any route from a virtual host.
   ```sh
   kubectl apply -f global-ratelimit/filter-ratelimit-svc.yaml 
   ```
   

### Test

To test the global rate limit in action, run the following command in a terminal 
session:

```sh 
ISTIO_INGRESS_URL=$(kubectl get svc istio-ingress -n istio-ingress -o jsonpath='{.status.loadBalancer.ingress[*].hostname}')

for i in {1..6}; do curl -Is $ISTIO_INGRESS_URL; done
```

In the output you should notice that the first 5 requests will generate 
output similar to the one below:

```
HTTP/1.1 200 OK
x-powered-by: Express
content-type: text/html; charset=utf-8
content-length: 1203
etag: W/"4b3-KO/ZeBhhZHNNKPbDwPiV/CU2EDU"
date: Wed, 17 Jan 2024 16:53:23 GMT
x-envoy-upstream-service-time: 34
server: istio-envoy
```

And the last request should generate output similar to:

```
HTTP/1.1 429 Too Many Requests
x-envoy-ratelimited: true
date: Wed, 17 Jan 2024 16:53:35 GMT
server: istio-envoy
transfer-encoding: chunked
```

We see this behavior because of the global rate limiting that is in effect that 
is allowing only a max of **5 requests/minute** when the context-path is `/`

## Reset the environment

Execute the following command to remove all rate-limiting configuration and 
services  and then run the same steps as in the [Initial state setup](#initial-state-setup) 
to reset the environment one last time.

```sh
# Delete all rate limiting configuration and services
kubectl delete -f ./local-ratelimit
kubectl delete -f ./global-ratelimit  
```