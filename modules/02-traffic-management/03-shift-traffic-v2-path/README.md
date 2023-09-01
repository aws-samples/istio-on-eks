# Module 2 - Traffic Management
## Section 3 - Shift traffic to v2 based on path

In this step we shift traffic to `v2` version of the `catalogdetail` service based on request URI path. The `productcatalog` service uses `AGG_APP_URL` environment variable to lookup and invoke the `catalogdetail` service. The environment variable is updated from

```
AGG_APP_URL=http://catalogdetail.workshop.svc.cluster.local:3000/catalogDetail
```

to

```
AGG_APP_URL=http://catalogdetail.workshop.svc.cluster.local:3000/v2/catalogDetail
```

The [`catalogdetail`](./catalogdetail-virtualservice.yaml) `VirtualService` is updated with an exact
URI path match on `/v2/catalogDetail` to route requests to `v2` subset. A URI rewrite rule reverts the
path from `/v2/catalogDetail` back to `/catalogDetail` before forwarding the request to the destination
pod.

### Deploy

```bash
# Change directory to the right folder
cd ../03-shift-traffic-v2-path

# Update route to send requests to /v2/catalogdetail to version v2.
kubectl apply -f catalogdetail-virtualservice.yaml
```

Output should be similar to:
```bash
virtualservice.networking.istio.io/catalogdetail configured
```

Set the environment variable in `productcatalog` for `catalogdetail` service.

```bash
# Set service endpoint environment variable in productcatalog.
kubectl set env deployment/productcatalog -n workshop AGG_APP_URL=http://catalogdetail.workshop.svc.cluster.local:3000/v2/catalogDetail
```

Output should be similar to:
```bash
deployment.apps/productcatalog env updated
```

### Validate

Verify that the `productcatalog` deployment has rolled out a new pod with the new environment variable.

```bash
kubectl describe deployment/productcatalog -n workshop
```

Output should be similar to:
```bash
Name:                   productcatalog
Namespace:              workshop
CreationTimestamp:      Fri, 01 Sep 2023 11:59:30 +0100
Labels:                 app.kubernetes.io/managed-by=Helm
Annotations:            deployment.kubernetes.io/revision: 2
                        meta.helm.sh/release-name: mesh-basic
                        meta.helm.sh/release-namespace: workshop
Selector:               app=productcatalog,version=v1
Replicas:               1 desired | 1 updated | 1 total | 1 available | 0 unavailable
StrategyType:           RollingUpdate
MinReadySeconds:        0
RollingUpdateStrategy:  25% max unavailable, 25% max surge
Pod Template:
  Labels:           app=productcatalog
                    version=v1
  Annotations:      sidecar.opentelemetry.io/inject: true
  Service Account:  productcatalog-sa
  Containers:
   productcatalog:
    Image:      public.ecr.aws/u2g6w7p2/eks-workshop-demo/product_catalog:1.0
    Port:       5000/TCP
    Host Port:  0/TCP
    Liveness:   http-get http://:5000/products/ping delay=0s timeout=1s period=10s #success=1 #failure=3
    Readiness:  http-get http://:5000/products/ping delay=0s timeout=1s period=10s #success=3 #failure=3
    Environment:
      AGG_APP_URL:  http://catalogdetail.workshop.svc.cluster.local:3000/v2/catalogDetail
    Mounts:         <none>
  Volumes:          <none>
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
OldReplicaSets:  productcatalog-5b79cb8dbb (0/0 replicas created)
NewReplicaSet:   productcatalog-69f56d4d8f (1/1 replicas created)
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  54s   deployment-controller  Scaled up replica set productcatalog-69f56d4d8f to 1
  Normal  ScalingReplicaSet  44s   deployment-controller  Scaled down replica set productcatalog-5b79cb8dbb to 0 from 1
```

#### Istio Resources

Run the following command to describe the [`catalogdetail`](./catalogdetail-virtualservice.yaml) `VirtualService`. Verify that the URI match and rewrite settings for `v2` are updated.

```bash
kubectl describe VirtualService catalogdetail -n workshop
```

Output should be similar to:
```bash
Name:         catalogdetail
Namespace:    workshop
Labels:       <none>
Annotations:  <none>
API Version:  networking.istio.io/v1beta1
Kind:         VirtualService
Metadata:
  Creation Timestamp:  2023-09-01T11:23:51Z
  Generation:          5
  Resource Version:    419539
  UID:                 651d4441-2db9-45f6-b0b8-ebbe76855c74
Spec:
  Hosts:
    catalogdetail
  Http:
    Match:
      Uri:
        Exact:  /v2/catalogDetail
    Rewrite:
      Uri:  /catalogDetail
    Route:
      Destination:
        Host:  catalogdetail
        Port:
          Number:  3000
        Subset:    v2
    Route:
      Destination:
        Host:  catalogdetail
        Port:
          Number:  3000
        Subset:    v1
Events:            <none>
```

### Test

#### Generating Traffic

Use the `siege` command line tool, generate traffic to the HTTP endpoint 
`http://$ISTIO_INGRESS_URL` noted above in the deployment output by running the following
command in a separate terminal session.

```sh 
# Generate load for 2 minute, with 5 concurrent threads and with a delay of 10s
# between successive requests
siege http://$ISTIO_INGRESS_URL -c 5 -d 10 -t 2M
```

While the load is being generated access the `kiali` console you previously 
configured and you should notice the traffic to be flowing in the manner shown
below:

![Traffic distribution](../../../static/images/02-traffic-management/03-shift-traffic-v2-path/traffic-distribution.png)

The traffic distribution for `catalogdetail` shows 100% of requests are routed to `v2` version.

### Destroy

Revert the change to the environment variable.

```bash
kubectl set env deployment/productcatalog -n workshop AGG_APP_URL=http://catalogdetail.workshop.svc.cluster.local:3000/catalogDetail
```