# Module 2 - Traffic Management
## Section 2 - Shift traffic to v2 based on weight

In this step we start shifting roughly 10% of traffic to `catalogdetail` virtual service to `v2` version.

### Deploy

```bash
# Change directory to the right folder
cd ../02-shift-traffic-v2-weight

# Update route to add 90% weight to subset: v1 and 10% weight to subset: v2
kubectl apply -f catalogdetail-virtualservice.yaml
```

Output should be similar to:
```bash
virtualservice.networking.istio.io/catalogdetail configured
```

### Validate

#### Istio Resources

Run the following command to describe the [`catalogdetail`](./catalogdetail-virtualservice.yaml) `VirtualService`.

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
  Generation:          3
  Resource Version:    396580
  UID:                 651d4441-2db9-45f6-b0b8-ebbe76855c74
Spec:
  Hosts:
    catalogdetail
  Http:
    Route:
      Destination:
        Host:  catalogdetail
        Port:
          Number:  3000
        Subset:    v1
      Weight:      90
      Destination:
        Host:  catalogdetail
        Port:
          Number:  3000
        Subset:    v2
      Weight:      10
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

![Traffic distribution](../../../static/images/02-traffic-management/02-shift-traffic-v2-weight/traffic-distribution.png)

The traffic distribution for `catalogdetail` shows almost 87% is randomly routed to `v1` version and only 13% is routed to `v2` version.

### Destroy