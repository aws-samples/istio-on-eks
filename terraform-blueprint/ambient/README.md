# Amazon EKS Auto Mode Cluster w/ Istio (`Ambient` mode)

This example demonstrates provisioning an EKS Auto Mode cluster with Istio in `Ambient` mode.

- Deploy an EKS Auto Mode cluster in a VPC. Auto Mode automatically manages compute, networking, and security group configurations.
- Install Istio in `Ambient` mode using Helm resources in Terraform.
- Deploy/Validate Istio communication using a sample application.

Refer to the [Istio documentation](https://istio.io/latest/docs/concepts/) for detailed explanations of Istio concepts.

## Deploy

Refer to the [prerequisites](https://aws-ia.github.io/terraform-aws-eks-blueprints/getting-started/#prerequisites) and run the following command to deploy this pattern:

```sh
cd terraform-blueprint/ambient
terraform init
terraform apply --auto-approve
aws eks --region us-west-2 update-kubeconfig --name ambient
```



### Observability Add-ons

Use the following code snippet to add the Istio Observability Add-ons (Kiali and Prometheus) on the EKS cluster with deployed Istio.

```sh
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/addons/prometheus.yaml \
  -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/addons/kiali.yaml
```

### Kubernetes Gateway API CRDs (Optional)

EKS clusters don't include [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) custom resource definitions (CRDs) by default. The Gateway API is an open source standard interface for Kubernetes application networking and represents the next generation of managing ingress and service mesh traffic within a cluster. Istio supports the Kubernetes Gateway API, and you need these resources to allow ingress traffic into your cluster and to manage ambient mesh traffic.

> **Note:** There is a Gateway resource in the Istio APIs, but this walkthrough doesn't use that resource. There are [key differences](https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/) between the two.

Install the Gateway API CRDs if they are not already present on your cluster:

```sh
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
  kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
```

**Why do you need this?**

- **Gateway**: A Gateway helps route traffic from outside the cluster to services running within it. Each Gateway is associated with a GatewayClass, which indicates the gateway controller (in this case, Istio) that handles the traffic for that Gateway. By default, Istio creates a ServiceAccount, Service, and Deployment that correspond to the Gateway configuration. If you need to adjust the settings of the underlying resources, you can create a ConfigMap and associate it with the Gateway resource.
- **HTTPRoute**: Route resources define rules for mapping requests through a Gateway to backend Kubernetes services. The HTTPRoute is specifically for the HTTP protocol and routes requests to your application services (e.g., the UI service).

## Validate

1. List out all pods and services in the `istio-system` namespace:

    ```sh
    kubectl get pods,svc -n istio-system
    ```

    ```text
    NAMESPACE      NAME                          READY   STATUS    RESTARTS   AGE
    istio-system   grafana-6c689999f9-5lk9b      1/1     Running   0          37s
    istio-system   istio-cni-node-28w2s          1/1     Running   0          10m
    istio-system   istio-cni-node-v4fc8          1/1     Running   0          12m
    istio-system   istiod-759544898-n84g5        1/1     Running   0          12m
    istio-system   kiali-95cffb658-8dp42         1/1     Running   0          10m
    istio-system   prometheus-6bd68c5c99-z6flt   2/2     Running   0          10m
    istio-system   ztunnel-82xvq                 1/1     Running   0          12m
    istio-system   ztunnel-csb26                 1/1     Running   0          10m

    NAME                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                                 AGE
    service/grafana      ClusterIP   172.20.210.200   <none>        3000/TCP                                2m14s
    service/istiod       ClusterIP   172.20.80.137    <none>        15010/TCP,15012/TCP,443/TCP,15014/TCP   14m
    service/kiali        ClusterIP   172.20.65.49     <none>        20001/TCP,9090/TCP                      12m
    service/prometheus   ClusterIP   172.20.141.251   <none>        9090/TCP                                12m


2. Verify all the Helm releases installed in the `istio-system` and `istio-ingress` namespaces:

    ```sh
    helm list -n istio-system
    ```

    ```text
    NAME            NAMESPACE       REVISION        UPDATED                                 STATUS          CHART             APP VERSION
    istio-base      istio-system    1               2026-03-19 21:14:27.275765 -0400 EDT    deployed        base-1.28.1       1.28.1
    istio-cni       istio-system    1               2026-03-19 21:14:19.6922 -0400 EDT      deployed        cni-1.28.1        1.28.1
    istiod          istio-system    1               2026-03-19 21:14:17.901337 -0400 EDT    deployed        istiod-1.28.1     1.28.1
    ztunnel         istio-system    1               2026-03-19 21:14:23.912003 -0400 EDT    deployed        ztunnel-1.28.1    1.28.1
    ```


### Observability Add-ons

Validate the setup of the observability add-ons by running the following commands
and accessing each of the service endpoints using this URL of the form
[http://localhost:\<port>](http://localhost:<port>) where `<port>` is one of the
port number for the corresponding service.

```sh
# Visualize Istio Mesh console using Kiali
kubectl port-forward svc/kiali 20001:20001 -n istio-system

# Get to the Prometheus UI
kubectl port-forward svc/prometheus 9090:9090 -n istio-system

# Visualize metrics in using Grafana
kubectl port-forward svc/grafana 3000:3000 -n istio-system

```

### Deploy Sample EKS Application

To demonstrate Istio's capabilities, deploy the [retail store sample application](https://github.com/aws-containers/retail-store-sample-app). This microservices-based app includes components written in various programming languages with different data stores. By default, the UI service is set to `LoadBalancer`, but you'll update it to `ClusterIP` and let Istio handle traffic into the cluster via the Gateway API. Run the following commands in a second terminal session.

#### Cart

```sh
helm install cart oci://public.ecr.aws/aws-containers/retail-store-sample-cart-chart --version 1.3.0
```

#### Catalog

```sh
helm install catalog oci://public.ecr.aws/aws-containers/retail-store-sample-catalog-chart --version 1.3.0
```

#### Checkout

```sh
cat > checkout-values.yaml <<EOF
redis:
  create: true
app:
  persistence:
    provider: redis
  endpoints:
    orders: 'http://orders:80'
EOF
```

```sh
helm install -f checkout-values.yaml checkout oci://public.ecr.aws/aws-containers/retail-store-sample-checkout-chart --version 1.3.0
```

#### Orders

```sh
helm install orders oci://public.ecr.aws/aws-containers/retail-store-sample-orders-chart --version 1.3.0
```

#### UI

```sh
cat > ui-values.yaml <<EOF
app:
  endpoints:
    carts: http://cart-carts:80
    catalog: http://catalog:80
    checkout: http://checkout:80
    orders: http://orders:80
EOF
```

```sh
helm install -f ui-values.yaml ui oci://public.ecr.aws/aws-containers/retail-store-sample-ui-chart --version 1.3.0
```

```sh
kubectl wait --for=condition=Ready --timeout=120s pods --all
```

#### Expose the Application using Kubernetes Gateway API

Use the Kubernetes Gateway API (installed above) to expose the retail store application and route external traffic into the cluster through Istio. This creates a Gateway with an NLB, scoped to your IP.

```sh
export USER_IP=$(curl https://checkip.amazonaws.com/)

cat <<EOF | envsubst | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: retail-store-gateway
  namespace: istio-ingress
spec:
  gatewayClassName: istio
  infrastructure:
    parametersRef:
      group: ""
      kind: ConfigMap
      name: retail-store-gateway-options
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: retail-store-gateway-options
  namespace: istio-ingress
data:
  service: |
    metadata:
      annotations:
        service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
        service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
        service.beta.kubernetes.io/aws-load-balancer-attributes: load_balancing.cross_zone.enabled=true
    spec:
      loadBalancerSourceRanges:
        - ${USER_IP}/32
EOF
```

> **Note:** Security - Since this NLB is internet-facing, `loadBalancerSourceRanges` restricts the NLB's security group to only allow inbound traffic from your public IP (`${USER_IP}/32`). Without this, the NLB would be open to `0.0.0.0/0`. You can verify this in the AWS Console under **EC2 → Load Balancers → Security → Inbound rules**, where `loadBalancerSourceRanges` gets translated into a security group inbound rule scoped to your IP, below is the reference.

![loadBalancerSourceRanges Security Group](../../images/loadBalancerSourceRanges.png)


#### HTTPRoute to expose the UI service
```sh
kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: retail-store-httproute
  namespace: default
spec:
  parentRefs:
    - name: retail-store-gateway
      namespace: istio-ingress
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: ui
          port: 80
EOF
```

Wait for the load balancer to finish provisioning, then verify the application is reachable:

```sh
curl --head -X GET --retry 30 --retry-all-errors --retry-delay 15 --connect-timeout 30 --max-time 60 \
  -k $(kubectl get gateway retail-store-gateway -n istio-ingress -ojsonpath='{.status.addresses[0].value}')
```

#### Response
```sh
HTTP/1.1 200 OK
content-type: text/html
content-language: en-US
set-cookie: SESSIONID=e3bf2d47-6604-40ba-93e6-8e3efb5d115f
content-length: 19973
x-envoy-upstream-service-time: 636
date: Tue, 24 Mar 2026 23:51:35 GMT
server: istio-envoy

Time: 0h:00m:04s
```


#### Add Workloads to the Ambient Mesh

To verify that workloads in the default namespace are included in the ambient mesh, label the namespace:

```sh
kubectl label namespace default istio.io/dataplane-mode=ambient
```

Run the following commands to get the URL to access the example retail store application:

```sh
export NLB_HOST=$(kubectl get gateway retail-store-gateway -n istio-ingress -ojsonpath='{.status.addresses[0].value}')
echo http://$NLB_HOST
```

## Destroy

Clean up the sample application resources before destroying the infrastructure:

```sh
kubectl delete HTTPRoute retail-store-httproute
kubectl delete Gateway retail-store-gateway -n istio-ingress
kubectl delete cm retail-store-gateway-options -n istio-ingress

helm uninstall ui
helm uninstall orders
helm uninstall checkout
helm uninstall catalog
helm uninstall cart

rm checkout-values.yaml
rm ui-values.yaml
```

```sh
terraform destroy --auto-approve
```