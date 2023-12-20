# Module 3 - Rate Limiting
This module shows the rate limiting capabilities of Istio service-mesh on Amazon EKS.

## Prerequisites:

- [Module 1 - Getting Started](../01-getting-started/)

Note: This module will build on the application resources deployed in [Module 1 - Getting Started](../01-getting-started/). That means you **don't** have to execute the [Destroy](../01-getting-started/README.md#destroy) section in Module 1.

## Initial state setup

In this step we add the Istio mesh resources to wrap the `frontend`, `productcatalog` and
`catalogdetail` services.

A [`DestinationRule`](https://istio.io/latest/docs/reference/config/networking/destination-rule/) is created for [`catalogdetail`](./setup-mesh-resources/catalogdetail-destinationrule.yaml) to select subsets
based on the `version` label of the destination pods. However, the initial [`VirtualService`](./setup-mesh-resources/catalogdetail-virtualservice.yaml) definition does not specify any 
subset configuration thereby leading to a uniform traffic spread across both subsets.

### Deploy 

```bash
# Change directory to the right folder
cd ../03-rate-limiting

# Install the mesh resources
kubectl apply -f ./setup-mesh-resources/
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

## Local Rate Limiting

#### Apply Local Rate Limiting to the ProdCatalog Service

```bash
kubectl apply -f local-ratelimit.yaml
```

The contents of the file are:

```
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: filter-local-ratelimit-svc
  namespace: istio-system
spec:
  workloadSelector:
    labels:
      app: productcatalog
  configPatches:
    - applyTo: HTTP_FILTER
      match:
        context: SIDECAR_INBOUND
        listener:
          filterChain:
            filter:
              name: "envoy.filters.network.http_connection_manager"
      patch:
        operation: INSERT_BEFORE
        value:
          name: envoy.filters.http.local_ratelimit
          typed_config:
            "@type": type.googleapis.com/udpa.type.v1.TypedStruct
            type_url: type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3.LocalRateLimit
            value:
              stat_prefix: http_local_rate_limiter
              enable_x_ratelimit_headers: DRAFT_VERSION_03
              token_bucket:
                max_tokens: 10
                tokens_per_fill: 10
                fill_interval: 60s
              filter_enabled:
                runtime_key: local_rate_limit_enabled
                default_value:
                  numerator: 100
                  denominator: HUNDRED
              filter_enforced:
                runtime_key: local_rate_limit_enforced
                default_value:
                  numerator: 100
                  denominator: HUNDRED
              response_headers_to_add:
                - append: false
                  header:
                    key: x-local-rate-limit
                    value: 'true'
```

1. The **HTTP_FILTER** patch inserts the `envoy.filters.http.local_ratelimit` [local envoy filter](https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/local_rate_limit_filter#config-http-filters-local-rate-limit) into the HTTP connection manager filter chain. 

1. The local rate limit filter’s [token bucket](https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/filters/http/local_ratelimit/v3/local_rate_limit.proto#envoy-v3-api-field-extensions-filters-http-local-ratelimit-v3-localratelimit-token-bucket) is configured to allow 10 requests/min. 

1. The filter is also configured to add an **x-local-rate-limit** response header to requests that are blocked.

### Validate

To test the rate limiter in action, exec into another pod and send a bunch of requests to the prodcatalog service to trigger the rate limiter. 

```bash
kubectl exec "$(kubectl get pod -l app=catalogdetail -o jsonpath='{.items[0].metadata.name}' -n workshop)" -c catalogdetail -n workshop --stdin --tty -- /bin/bash
 
for i in {1..20}; do curl -I http://productcatalog.workshop.svc.cluster.local:5000/products/; done
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

While a rate limited requests will return the following output:

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

Similarly, if you run the same shell command without `-I` flag, you’ll start seeing **local_rate_limited** responses for the requests that are rate limited. And it will look something like this:

```
{
    "products": {},
    "details": {
        "version": "2",             <---------- Successful response to the request
        "vendors": [
            "ABC.com, XYZ.com"
        ]
    }
}

local_rate_limited                  <---------- Rate limited requests
```

## Global Rate Limiting

#### Create ConfigMap for configuring the central rate limiting service

```bash
kubectl apply -f global-ratelimit-cm.yaml
```

The ConfigMap file looks like this:

```
apiVersion: v1
kind: ConfigMap
metadata: 
  name: ratelimit-config
  namespace: workshop
data: 
  config.yaml: |
    domain: prodcatalog-ratelimit
    descriptors: 
      - key: PATH
        value: "/"
        rate_limit:
          unit: minute
          requests_per_unit: 5
      - key: PATH
        rate_limit: 
          unit: minute
          requests_per_unit: 100
```

1. The above ConfigMap has the configuration for setting up the rate limit requests to the `/` path at **5 requests/minute** and all other requests at **100 requests/minute**.

#### Deploy the Global Rate Limit service along with Redis

```bash
kubectl apply -f global-server-configuration.yaml
```

NOTE: The above file deploys two Deployments, one for the Central Rate Limit Service and one for the Redis Instance. It also creates services for both the deployments. 

The cofiguration for the Global Rate Limit service looks like this:

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ratelimit
  namespace: workshop
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ratelimit
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: ratelimit
    spec:
      containers:
      - image: envoyproxy/ratelimit:9d8d70a8
        imagePullPolicy: Always
        name: ratelimit
        command: ["/bin/ratelimit"]
        env:
        - name: LOG_LEVEL
          value: debug
        - name: REDIS_SOCKET_TYPE
          value: tcp
        - name: REDIS_URL
          value: redis:6379
        - name: USE_STATSD
          value: "false"
        - name: RUNTIME_ROOT
          value: /data
        - name: RUNTIME_SUBDIRECTORY
          value: ratelimit
        - name: RUNTIME_WATCH_ROOT
          value: "false"
        - name: RUNTIME_IGNOREDOTFILES
          value: "true"
        - name: HOST
          value: "::"
        - name: GRPC_HOST
          value: "::"
        ports:
        - containerPort: 8080
        - containerPort: 8081
        - containerPort: 6070
        volumeMounts:
        - name: config-volume
          mountPath: /data/ratelimit/config
      volumes:
      - name: config-volume
        configMap:
          name: ratelimit-config
```

#### Apply configuration #1 to enable Global Rate Limit for the Ingress Gateway

```bash
kubectl apply -f global-ratelimit-1.yaml
```

The contents of the file looks like this:

```
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: filter-ratelimit
  namespace: istio-system
spec:
  workloadSelector:
    labels:
      istio: ingressgateway
  configPatches:
    # The Envoy config you want to modify
    - applyTo: HTTP_FILTER
      match:
        context: GATEWAY
        listener:
          filterChain:
            filter:
              name: "envoy.filters.network.http_connection_manager"
              subFilter:
                name: "envoy.filters.http.router"
      patch:
        operation: INSERT_BEFORE
        # Adds the Envoy Rate Limit Filter in HTTP filter chain.
        value:
          name: envoy.filters.http.ratelimit
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.filters.http.ratelimit.v3.RateLimit
            # domain can be anything! Match it to the ratelimter service config
            domain: prodcatalog-ratelimit
            failure_mode_deny: true
            timeout: 10s
            rate_limit_service:
              grpc_service:
                envoy_grpc:
                  cluster_name: outbound|8081||ratelimit.workshop.svc.cluster.local
                  authority: ratelimit.workshop.svc.cluster.local
              transport_api_version: V3
```

1. The above configration inserts the `envoy.filters.http.ratelimit` [global envoy filter](https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/filters/http/ratelimit/v3/rate_limit.proto#envoy-v3-api-msg-extensions-filters-http-ratelimit-v3-ratelimit) into the **HTTP_FILTER** chain.
1. The `rate_limit_service` field specifies the external rate limit service, `outbound|8081||ratelimit.workshop.svc.cluster.local` in this case.

#### Apply configuration #2 to the IngressGateway. 

This configuration defines the route on which rate limit with be applied. 

```bash
kubectl apply -f global-ratelimit-2.yaml
```

The contents of the file are:

```
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: filter-ratelimit-svc
  namespace: istio-system
spec:
  workloadSelector:
    labels:
      istio: ingressgateway
  configPatches:
    - applyTo: VIRTUAL_HOST
      match:
        context: GATEWAY
        routeConfiguration:
          vhost:
            name: ""
            route:
              action: ANY
      patch:
        operation: MERGE
        # Applies the rate limit rules.
        value:
          rate_limits:
            - actions: # any actions in here
              - request_headers:
                  header_name: ":path"
                  descriptor_key: "PATH"
```

1. The above configuration adds rate limit actions for any route from a virtual host.

### Validate

To test the global rate limit in action:

1. Access the basic app web ui and start refreshing the browser. Once you hit 5 refreshes within a minute the page will stop working

1. Send curl commands to the same url and grab the HTTP code. After hitting 5 curl commands within a minute, you will start seeing HTTP 429 response codes from the url.

## Cleanup

```
# Delete Global Rate Limit Configuration
kubectl delete -f global-ratelimit-2.yaml
kubectl delete -f global-ratelimit-1.yaml
kubectl delete -f global-server-configuration.yaml
kubectl delete -f global-ratelimit-cm.yaml

# Delete Local Rate Limit Configuration via Manifest File
kubectl delete -f local-ratelimit.yaml

# Delete Application Virtual Services
kubectl delete -f ./setup-mesh-resources/  
```

## Destroy

Refer to [Destroy](../01-getting-started/README.md#destroy) section for
cleanup of application resources.