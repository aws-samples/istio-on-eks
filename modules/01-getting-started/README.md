# Module 1 - Getting Started 

This module shows how to deploy microservices as part of Istio service-mesh on 
EKS

## Prerequisites:

To be able to work on this module you should have an EKS cluster with Istio deployed by following below steps.
1. You will need to clone the below repo.
   ```sh
   git clone https://github.com/aws-ia/terraform-aws-eks-blueprints.git
   cd terraform-aws-eks-blueprints/patterns/istio 
   ```
2. Then follow the [Istio EKS Blueprint](https://aws-ia.github.io/terraform-aws-eks-blueprints/patterns/istio/#deploy) setup.

3. Ensure that you have the following tools installed locally:

   1. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
   2. [helm](https://helm.sh/docs/intro/install/)
   3. [jq](https://jqlang.github.io/jq/download/)
   4. [siege](https://github.com/JoeDog/siege)

## Deploy 

```sh
# Change directory to the right folder
cd modules/01-getting-started

# Create workshop namespace 
kubectl create namespace workshop
kubectl label namespace workshop istio-injection=enabled

# Install all the microservices in one go
helm install mesh-basic . -n workshop
```

Output should be similar to:
```
namespace/workshop created
namespace/workshop labeled
NAME: mesh-basic
LAST DEPLOYED: Mon Aug 21 18:08:29 2023
NAMESPACE: workshop
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
1. Get the application URL by running the following command:

   ISTIO_INGRESS_URL=$(kubectl get svc istio-ingress -n istio-ingress -o jsonpath='{.status.loadBalancer.ingress[*].hostname}')
   echo "http://$ISTIO_INGRESS_URL"

2. Access the displayed URL in a terminal using cURL or via a browser window

Note: It may take a few minutes for the istio-ingress Network LoadBalancer to associate to the instance-mode targetGroup after the application is deployed.
```

## Validate

Validate the install of microservices in the `workshop` namespace by running:

```sh
kubectl get pods -n workshop
```

Output should be similar to:

```
NAME                              READY   STATUS    RESTARTS   AGE
catalogdetail-658d6dbc98-q544p    2/2     Running   0          7m19s
catalogdetail2-549877454d-kqk9b   2/2     Running   0          7m19s
frontend-7cc46889c8-qdhht         2/2     Running   0          7m19s
productcatalog-5b79cb8dbb-t9dfl   2/2     Running   0          7m19s
```

As can be noted in the output, each of the application pods is running two 
containers, an application container and an Istio proxy.

> Note: You can run the command `kubectl get pod <pod-name> -n workshop -o yaml`
on any of the above listed pods for further inspection of pod contents.

### Istio Resources

Run the following command to list all the Istio resources created.

```sh
kubectl get Gateway,VirtualService,DestinationRule -n workshop
```

Output should be similar to:
```
NAME                                                 AGE
gateway.networking.istio.io/productapp-gateway   7m50s

NAME                                                GATEWAYS                     HOSTS   AGE
virtualservice.networking.istio.io/productapp   ["productapp-gateway"]   ["*"]   7m50s
```

## Test

We will be using the deployed `kiali` to verify the interaction between the 
microservices that are deployed.

### Configure Kiali

Run the following command in a terminal session to port-forward `kiali` traffic 
on to a designated port on your localhost 

```sh 
kubectl port-forward svc/kiali 20001:20001 -n istio-system
```

Use your browser to navigate to `http://localhost:20001`. At the `kiali` console
carefully observe the highlighted portions of the image below and replicate that 
in your environment.

![](../../images/01-kiali-console.png)

### Generating Traffic

Use the `siege` command line tool, generate traffic to the HTTP endpoint 
`http://$ISTIO_INGRESS_URL` noted above in the deployment output by running the following
command in a separate terminal session.

```sh 
# Generate load for 2 minute, with 5 concurrent threads and with a delay of 10s
# between successive requests
ISTIO_INGRESS_URL=$(kubectl get service/istio-ingress -n istio-ingress -o json | jq -r '.status.loadBalancer.ingress[0].hostname')
siege http://$ISTIO_INGRESS_URL -c 5 -d 10 -t 2M
```

While the load is being generated access the `kiali` console you previously 
configured and you should notice the traffic to be flowing in the manner shown
below:

![](../../images/01-kiali-traffic-flow.gif)

Based on animation shown we conclude that:
1. The Ingress traffic directed towards the `istio-ingress` is captured by the 
Gateway `productapp-gateway` as it handles traffic for all hosts (*)
2. Traffic is then directed towards to `productapp` VirtualService as its 
`host` definition matches all hosts (*)
3. Traffic is then forwarded to `frontend` microservice as the context-path 
matches `/` and moves between microservices as shown in the GIF above.
4. The `catalogdetail` service, as expected, randomly splits the traffic between 
`v1` and `v2` versions.

## Destroy 

```sh
helm uninstall mesh-basic -n workshop
kubectl delete namespace workshop
```
