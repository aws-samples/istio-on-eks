# Module 3 - Network Resilience

This module shows the Network resilience and testing features like Timeouts, Retries and Circuit breakers of Istio service-mesh on Amazon EKS. The module is split into subdirectories for these 3 specific use cases.

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
cd ../03-network-resilience

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

### Timeouts

In this step, first add a delay of 5secs to catalogdetail virtual service.

```bash
kubectl apply -f catalogdetail-delay-virtualservice.yaml 
```

output should be similar to:

```bash                                                                 
virtualservice.networking.istio.io/catalogdetail configured
```

Now, we can see there is a delay of 5 seconds while loading the Product Catalog application

```bash  
curl http://a91bc63ae1c4343a08c91a2ec487e62e-4d2c547dc8131129.elb.us-east-1.amazonaws.com/ -s -o /dev/null -w  "%{time_starttransfer}\n"
5.022975
```

Now, add a timeout of 2 seconds for productcatalog virtual service.

```bash
kubectl apply -f productcatalog-timeout-virtualservice.yaml 
```

output should be similar to:

```bash                                                                 
virtualservice.networking.istio.io/productcatalog configured
```

To test timeout functionality, install multitools 

```bash  
kubectl create deployment multitool --image=praqma/network-multitool -n workshop
```

multitool pod has been deployed

```bash  
kubectl get pods -n workshop | grep multitool
multitool-86d6d5c595-b2pdh        2/2     Running   0          8m13s
```
then login to multitool pod and execute the command to see the timeout

```bash  
kubectl exec -n workshop -it multitool-86d6d5c595-b2pdh /bin/bash
curl http://productcatalog:5000/products/ -s -o /dev/null -w  "Time taken to start trasnfer: %{time_starttransfer}\n"
```
output should be similar to:

```bash 
Admin:~/environment/istio-on-eks/modules/03-network-resiliency (main) $ kubectl exec -n workshop -it multitool-86d6d5c595-b2pdh /bin/bash
kubectl exec [POD] [COMMAND] is DEPRECATED and will be removed in a future version. Use kubectl exec [POD] -- [COMMAND] instead.
Defaulting container name to network-multitool.
Use 'kubectl describe pod/multitool-86d6d5c595-b2pdh -n workshop' to see all of the containers in this pod.

bash-5.1# curl http://productcatalog:5000/products/ -s -o /dev/null -w  "Time taken to start trasnfer: %{time_starttransfer}\n"
Time taken to start trasnfer: 2.006628
```

![](../../../images/03-timeouts.png)

### Retries:

Let's add retries of 2 for productcatalog-retries-virtualservice.yaml 

```bash 
kubectl apply -f productcatalog-retries-virtualservice.yaml
```

output should be similar to:

```bash
virtualservice.networking.istio.io/productcatalog configured
```

To check the retries functionality, install istioctl

```bash
curl -sL https://istio.io/downloadIstioctl | sh -
export PATH=$HOME/.istioctl/bin:$PATH
istioctl x precheck
```
output should be similar to below

```bash
Admin:~/environment/istio-on-eks/modules/03-network-resiliency (main) $ curl -sL https://istio.io/downloadIstioctl | sh -

Downloading istioctl-1.19.3 from https://github.com/istio/istio/releases/download/1.19.3/istioctl-1.19.3-linux-amd64.tar.gz ...
istioctl-1.19.3-linux-amd64.tar.gz download complete!

Add the istioctl to your path with:
  export PATH=$HOME/.istioctl/bin:$PATH 

Begin the Istio pre-installation check by running:
         istioctl x precheck 

Need more information? Visit https://istio.io/docs/reference/commands/istioctl/

Admin:~/environment/istio-on-eks/modules/03-network-resiliency (main) $ export PATH=$HOME/.istioctl/bin:$PATH 

Admin:~/environment/istio-on-eks/modules/03-network-resiliency (main) $ istioctl x precheck 
Info [IST0136] (Pod istio-ingress/istio-ingress-5bc6c5b8f4-n6jw6) Annotation "inject.istio.io/templates" is part of an alpha-phase feature and may be incompletely supported.
Info [IST0136] (Pod istio-ingress/istio-ingress-5bc6c5b8f4-n6jw6) Annotation "proxy.istio.io/overrides" is part of an alpha-phase feature and may be incompletely supported.
Admin:~/environment/istio-on-eks/modules/03-network-resiliency (main) $
```

Debug mode is enabled for productcatalog as below

```bash
istioctl pc log --level debug -n workshop deploy/productcatalog
```
output should be similar to below

```bash
Admin:~/environment/istio-on-eks/modules/03-network-resiliency (main) $ istioctl pc log --level debug -n workshop deploy/productcatalog
productcatalog-5b79cb8dbb-r8ztn.workshop:
active loggers:
  admin: debug
  alternate_protocols_cache: debug
  aws: debug
  assert: debug
  backtrace: debug
  cache_filter: debug
  client: debug
  config: debug
  connection: debug
  conn_handler: debug
  decompression: debug
  dns: debug
  dubbo: debug
  envoy_bug: debug
  ext_authz: debug
  ext_proc: debug
  rocketmq: debug
  file: debug
  filter: debug
  forward_proxy: debug
  grpc: debug
  happy_eyeballs: debug
  hc: debug
  health_checker: debug
  http: debug
  http2: debug
  hystrix: debug
  init: debug
  io: debug
  jwt: debug
  kafka: debug
  key_value_store: debug
  lua: debug
  main: debug
  matcher: debug
  misc: debug
  mongo: debug
  multi_connection: debug
  oauth2: debug
  quic: debug
  quic_stream: debug
  pool: debug
  rate_limit_quota: debug
  rbac: debug
  rds: debug
  redis: debug
  router: debug
  runtime: debug
  stats: debug
  secret: debug
  tap: debug
  testing: debug
  thrift: debug
  tracing: debug
  upstream: debug
  udp: debug
  wasm: debug
  websocket: debug
  golang: debug
```

Refresh the browser and look at the logs to see the number of retries 

```bash
kubectl logs -f -n workshop -l app=productcatalog -c istio-proxy | grep "x-envoy-attempt-count"
```

Output should be similar to below as there are 2 retries (in addition to the first first request)

```bash 
Admin:~/environment/istio-on-eks/modules/03-network-resiliency (main) $ kubectl logs -f -n workshop -l app=productcatalog -c istio-proxy | grep "x-envoy-attempt-count"
'x-envoy-attempt-count', '1'
'x-envoy-attempt-count', '1'
'x-envoy-attempt-count', '1' 

```

### Circuit Breaking

Create a destination rule to apply circuit breaking settings when calling productcatalog service.

```bash 
kubectl apply -f catalog-destinationrule-circuitbreaker.yaml
```

Output should be similar to below

```bash 
destinationrule.networking.istio.io/catalogdetail created
```

Install [fortio](https://github.com/fortio/fortio)

```bash 
kubectl apply -f fortio.yaml
```

Output should be similar to below

```bash 
service/fortio created
deployment.apps/fortio-deploy created
```

Log in to the client pod and use the fortio tool to call prodcutcatalog. Pass in curl to indicate that you just want to make one call:

```bash
$ export FORTIO_POD=$(kubectl get pods -l app=fortio -o 'jsonpath={.items[0].metadata.name}')
kubectl exec "$FORTIO_POD" -c fortio -n workshop /usr/bin/fortio curl http://catalogdetail.workshop.svc.cluster.local:3000/catalogDetail
```

Output should be similar to below:

```bash
Admin:~/environment/istio-on-eks/modules/03-network-resiliency/fortio (main) $ kubectl exec "$FORTIO_POD" -c fortio -n workshop /usr/bin/fortio curl http://catalogdetail.workshop.svc.cluster.local:3000/catalogDetail
kubectl exec [POD] [COMMAND] is DEPRECATED and will be removed in a future version. Use kubectl exec [POD] -- [COMMAND] instead.
{"ts":1698264664.897093,"level":"info","r":1,"file":"scli.go","line":123,"msg":"Starting","command":"Φορτίο","version":"1.60.3 h1:adR0uf/69M5xxKaMLAautVf9FIVkEpMwuEWyMaaSnI0= go1.20.10 amd64 linux"}
HTTP/1.1 200 OK
x-powered-by: Express
content-type: application/json; charset=utf-8
content-length: 37
etag: W/"25-+DP7kANx3olb0HJqt5zDWgaO2Gg"
date: Wed, 25 Oct 2023 20:11:04 GMT
x-envoy-upstream-service-time: 6
server: envoy
 
{"version":"1","vendors":["ABC.com"]}
```

### Tripping the circuit breaker

```bash
kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 2 -qps 0 -n 20 -loglevel Warning http://catalogdetail.workshop.svc.cluster.local:3000/catalogDetail
``` 
Output should be similar to below:

```bash
Admin:~/environment/istio-on-eks/modules/03-network-resiliency/fortio (main) $ kubectl exec "$FORTIO_POD" -c fortio -- /usr/bin/fortio load -c 2 -qps 0 -n 20 -loglevel Warning http://catalogdetail.workshop.svc.cluster.local:3000/catalogDetail
{"ts":1698262242.288381,"level":"info","r":1,"file":"logger.go","line":254,"msg":"Log level is now 3 Warning (was 2 Info)"}
Fortio 1.60.3 running at 0 queries per second, 2->2 procs, for 20 calls: http://catalogdetail.workshop.svc.cluster.local:3000/catalogDetail
Starting at max qps with 2 thread(s) [gomax 2] for exactly 20 calls (10 per thread + 0)
Ended after 27.000998ms : 20 calls. qps=740.71
Aggregated Function Time : count 20 avg 0.002298304 +/- 0.002456 min 0.000835011 max 0.011417996 sum 0.04596608
# range, mid point, percentile, count
>= 0.000835011 <= 0.001 , 0.000917506 , 25.00, 5
> 0.001 <= 0.002 , 0.0015 , 75.00, 10
> 0.003 <= 0.004 , 0.0035 , 80.00, 1
> 0.004 <= 0.005 , 0.0045 , 95.00, 3
> 0.011 <= 0.011418 , 0.011209 , 100.00, 1
# target 50% 0.0015
# target 75% 0.002
# target 90% 0.00466667
# target 99% 0.0113344
# target 99.9% 0.0114096
Error cases : no data
# Socket and IP used for each connection:
[0]   1 socket used, resolved to 172.20.120.174:3000, connection timing : count 1 avg 0.000120428 +/- 0 min 0.000120428 max 0.000120428 sum 0.000120428
[1]   1 socket used, resolved to 172.20.120.174:3000, connection timing : count 1 avg 0.000564218 +/- 0 min 0.000564218 max 0.000564218 sum 0.000564218
Connection time (s) : count 2 avg 0.000342323 +/- 0.0002219 min 0.000120428 max 0.000564218 sum 0.000684646
Sockets used: 2 (for perfect keepalive, would be 2)
Uniform: false, Jitter: false, Catchup allowed: true
IP addresses distribution:
172.20.120.174:3000: 2
Code 200 : 20 (100.0 %)
Response Header Sizes : count 20 avg 1344 +/- 5 min 1339 max 1349 sum 26880
Response Body/Total Sizes : count 20 avg 1385.5 +/- 9.5 min 1376 max 1395 sum 27710
All done 20 calls (plus 0 warmup) 2.298 ms avg, 740.7 qps
```
