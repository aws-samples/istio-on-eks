# Module 2 - Traffic Management
## Section 1 - Setup default route to v1

In this step we setup default route for `catalogdetail` virtual service to 
route all traffic to `v1` version.

### Deploy

```bash
# Change directory to the right folder
cd ../01-default-route-v1

# Update route to add subset: v1
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
  Generation:          2
  Resource Version:    379088
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

![Traffic distribution](../../../static/images/02-traffic-management/01-default-route-v1/traffic-distribution.png)

The traffic distribution for `catalogdetail` shows all traffic is now routed
to only `v1` version.

### Destroy