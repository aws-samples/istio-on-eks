# Security - Peer Authentication

This sub-module focuses on enforcing mutual TLS using AWS Private CA for **Peer Authentication** on Amazon EKS.

This will be achieved through [`cert-manager`](https://cert-manager.io/) integrations.

The below projects will be used to integrate Istio with AWS Private CA:

  * [aws-privateca-issuer](https://github.com/cert-manager/aws-privateca-issuer/tree/main) - addon for cert-manager that issues certificates using AWS ACM PCA
  * [istio-csr](https://github.com/cert-manager/istio-csr) - an agent that allows for Istio workload and control plane components to be secured using cert-manager

## Deploy

It is recommended to install all the dependencies for certificate management like `cert-manager`, `aws-privateca-issuer` and `istio-csr` before installing Istio control plane to avoid issues with CA migration. Refer to [Installing istio-csr After Istio](https://cert-manager.io/docs/usage/istio-csr/#installing-istio-csr-after-istio) for more details.

### Uninstall Istio

Navigate to the previously cloned `terraform-aws-eks-blueprints` project directory and uninstall Istio using `terraform destroy` command.

```bash
# The below directory path assumes that the current working directory
# is `istio-on-eks/modules/04-security`.
# Also it is assumed that the `terraform-aws-eks-blueprints`
# project is cloned in the same parent directory as `istio-on-eks`.
# Change the directory path based on your current directory.
cd ../../../terraform-aws-eks-blueprints/patterns/istio
terraform destroy -target='kubernetes_namespace_v1.istio_system' -auto-approve
```

### Install dependencies for certificate management

Now that Istio is uninstalled navigate back to the security module directory to continue with the certificate management dependency installation steps.

```bash
# The below directory path assumes that terraform-aws-eks-blueprints and istio-on-eks projects are cloned in the same parent directory
cd ../../../istio-on-eks/modules/04-security
```

The peer authentication section uses AWS Private CA to issue certificates to the mesh workloads and the ingress gateway load balancer. Note that your account is charged a monthly price for each private CA starting from the time that you create it. You are also charged for each certificate that is issued by the Private CA. Refer to [AWS Private CA Pricing](https://aws.amazon.com/private-ca/pricing/) for more details.

By default the terraform setup module will create a new Private CA resource. You can override this by exporting a well known variable pointing to the
ARN of an existing Private CA.

Run the below terraform commands to setup the resources for peer authentication.

*If setting up with a new Private CA resource:*

```bash
terraform init
terraform apply -target='module.setup_peer_authentication' -auto-approve
```

*or to point to an existing Private CA:*

```bash
terraform init
export TF_VAR_aws_privateca_arn=arn:aws:acm-pca:{region}:{account-id}:certificate-authority/{id}
terraform apply -target='module.setup_peer_authentication' -auto-approve
```

**Note:** Replace the placeholders for region (`{region}`), account id (`{account-id}`) and certificate id (`{id}`) in the above environment variable export command.

This will first install the necessary dependencies and then reinstall Istio with updated TLS settings. Once the resources have been provisioned, you will need to replace the `istio-ingress` pods due to a [`istiod` dependency issue](https://github.com/istio/istio/issues/35789). Use the following command to perform a rolling restart of the `istio-ingress` pods:

```sh
kubectl rollout restart deployment istio-ingress -n istio-ingress
```

Reinstall the Istio observability addons.

```sh
for ADDON in kiali jaeger prometheus grafana
do
    ADDON_URL="https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/$ADDON.yaml"
    kubectl apply -f $ADDON_URL
done
```

## Validate

Verify that all pods are running.

```bash
kubectl get pods -n cert-manager
kubectl get pods -n aws-privateca-issuer
kubectl get pods -n istio-system
kubectl get pods -n istio-ingress
```

Make sure that the output shows all pods are in `Running` status.

```
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-6d988558d6-tgwrc              1/1     Running   0          3m32s
cert-manager-cainjector-6976895488-m5sht   1/1     Running   0          3m32s
cert-manager-csi-driver-76jtg              3/3     Running   0          3m
cert-manager-csi-driver-zx68p              3/3     Running   0          3m
cert-manager-istio-csr-f87db45fb-78czj     1/1     Running   0          2m39s
cert-manager-webhook-fcf48cc54-g7d5t       1/1     Running   0          3m32s
NAME                                   READY   STATUS    RESTARTS   AGE
aws-privateca-issuer-776554d88-72jjq   1/1     Running   0          3m55s
NAME                         READY   STATUS    RESTARTS   AGE
grafana-b8bbdc84d-46hvm      1/1     Running   0          50s
istiod-84d6bb5f7d-krkgp      1/1     Running   0          97s
jaeger-7d7d59b9d-k95f5       1/1     Running   0          60s
kiali-545878ddbb-ptsdn       1/1     Running   0          62s
prometheus-db8b4588f-d6g98   2/2     Running   0          54s
NAME                             READY   STATUS    RESTARTS   AGE
istio-ingress-845d676c6b-rsh8c   1/1     Running   0          83s
```

Verify that AWS PrivateCA Issuer named `root-ca` is `Ready`.

```bash
kubectl get awspcaissuer/root-ca -n istio-system \
  -o custom-columns='NAME:.metadata.name,CONDITION_MSG:.status.conditions[*].message,CONDITION_REASON:.status.conditions[*].reason,CONDITION_STATUS:.status.conditions[*].status,CONDITION_TYPE:.status.conditions[*].type'
```

The output should look similar to below sample output.

```
NAME      CONDITION_MSG     CONDITION_REASON   CONDITION_STATUS   CONDITION_TYPE
root-ca   Issuer verified   Verified           True               Ready
```

Verify that the intermediate CA certificate issuer `istio-ca`, CA certificate `istio-ca` and `istiod` certificate are all created and all report `READY=True`:

```bash
kubectl get issuers,certificates -n istio-system
```

The output should be similar to the below sample output.

```
NAME                              READY   AGE
issuer.cert-manager.io/istio-ca   True    4m36s

NAME                                   READY   SECRET       AGE
certificate.cert-manager.io/istio-ca   True    istio-ca     4m36s
certificate.cert-manager.io/istiod     True    istiod-tls   4m19s
```

Verify that a secret containing the intermediate CA certificate named `istio-ca` has been created and chains up to the root CA certificate from AWS Private CA.

```bash
kubectl get secret/istio-ca -n istio-system -o jsonpath='{.data.tls\.crt}' \
  | base64 -d \
  | openssl x509 -text -noout
```

Output should be similar to below.

```
Certificate:
    Data:
        ...
        Signature Algorithm: sha512WithRSAEncryption
        Issuer: CN = Istio on EKS PrivateCA
        Validity
            Not Before: Apr 17 15:33:12 2024 GMT
            Not After : Jul 16 16:33:12 2024 GMT
        Subject: O = cert-manager, CN = istio-ca
        ...
        X509v3 extensions:
            X509v3 Basic Constraints: critical
                CA:TRUE, pathlen:0
            ...
            X509v3 Key Usage: critical
                Digital Signature, Certificate Sign, CRL Sign
    Signature Algorithm: sha512WithRSAEncryption
    ...
```

In the output, note that the certificate is a CA certificate and the Organization (`O`) shows as `cert-manager` and common name (`CN`) shows as `istio-ca`. This will be validated later when inspecting the workload certificates. The issuer `CN` should match the AWS PrivateCA certificate CN value.

Setup environment variables to inspect the workload TLS settings.

```bash
# Set namespace for sample application
export NAMESPACE=workshop
# Set env var for the value of the app label in manifests
export APP=frontend
```

In a separate terminal window you should now follow the logs for cert-manager:

```bash
kubectl logs -n cert-manager $(kubectl get pods -n cert-manager -o jsonpath='{.items..metadata.name}' --selector app=cert-manager) --since 2m -f
```

In another separate terminal window, lets watch the istio-system namespace for certificaterequests:

```bash
kubectl get certificaterequests.cert-manager.io -n istio-system -w
```

Now in the original terminal window deploy the workshop helm chart following the instructions in [Module 1: Deploy](/modules/01-getting-started/README.md#deploy).

You should see something similar to the output here for `certificaterequests` as the application pods are materialized.

```
istio-csr-czrhx                               istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
istio-csr-czrhx   True                        istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
istio-csr-czrhx   True                True    istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
istio-csr-czrhx   True                True    istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
istio-csr-xwwzs                               istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
istio-csr-xwwzs   True                        istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
istio-csr-mt8dn                               istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
istio-csr-mt8dn   True                        istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
istio-csr-r82vl                               istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
istio-csr-xwwzs   True                True    istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   1s
istio-csr-r82vl   True                        istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
istio-csr-mt8dn   True                True    istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
istio-csr-xwwzs   True                True    istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   1s
istio-csr-mt8dn   True                True    istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
istio-csr-r82vl   True                True    istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
istio-csr-r82vl   True                True    istio-ca   system:serviceaccount:cert-manager:cert-manager-istio-csr   0s
```

The key requests being `istio-csr-czrhx`, `istio-csr-xwwzs`, `istio-csr-mt8dn`, and `istio-csr-r82vl` corresponding
to the four application pods in the example output.
The `cert-manager` log output for two log lines for each request being "Approved" and "Ready":

```
I0417 17:10:37.345804       1 conditions.go:263] Setting lastTransitionTime for CertificateRequest "istio-csr-czrhx" condition "Approved" to 2024-04-17 17:10:37.345791712 +0000 UTC m=+2275.578687711
I0417 17:10:37.376320       1 conditions.go:263] Setting lastTransitionTime for CertificateRequest "istio-csr-czrhx" condition "Ready" to 2024-04-17 17:10:37.376309942 +0000 UTC m=+2275.609205934
I0417 17:10:48.665420       1 conditions.go:263] Setting lastTransitionTime for CertificateRequest "istio-csr-xwwzs" condition "Approved" to 2024-04-17 17:10:48.665408707 +0000 UTC m=+2286.898304707
I0417 17:10:49.410183       1 conditions.go:263] Setting lastTransitionTime for CertificateRequest "istio-csr-mt8dn" condition "Approved" to 2024-04-17 17:10:49.410172176 +0000 UTC m=+2287.643068174
I0417 17:10:49.478161       1 conditions.go:263] Setting lastTransitionTime for CertificateRequest "istio-csr-xwwzs" condition "Ready" to 2024-04-17 17:10:49.478148037 +0000 UTC m=+2287.711044034
I0417 17:10:49.553203       1 conditions.go:263] Setting lastTransitionTime for CertificateRequest "istio-csr-r82vl" condition "Approved" to 2024-04-17 17:10:49.553191856 +0000 UTC m=+2287.786087890
I0417 17:10:49.556293       1 conditions.go:263] Setting lastTransitionTime for CertificateRequest "istio-csr-mt8dn" condition "Ready" to 2024-04-17 17:10:49.556280951 +0000 UTC m=+2287.789176953
I0417 17:10:49.836643       1 conditions.go:263] Setting lastTransitionTime for CertificateRequest "istio-csr-r82vl" condition "Ready" to 2024-04-17 17:10:49.836631125 +0000 UTC m=+2288.069527118
```

Verify that all workload pods are running with both the application container and the sidecar.

```bash
kubectl get pods -n $NAMESPACE
```

To validate that the `istio-proxy` sidecar container has requested the certificate from the correct service, check the container logs:

```bash
kubectl logs $(kubectl get pod -n $NAMESPACE -o jsonpath="{.items...metadata.name}" --selector app=$APP) -c istio-proxy -n $NAMESPACE | grep cert-manager
```

There should be matching log lines similar to the sample output below.

```
2024-04-17T17:10:47.792253Z     info    CA Endpoint cert-manager-istio-csr.cert-manager.svc:443, provider Citadel
2024-04-17T17:10:47.792274Z     info    Using CA cert-manager-istio-csr.cert-manager.svc:443 cert with certs: var/run/secrets/istio/root-cert.pem
```

Finally, inspect the certificate being used in memory by Envoy. Verify that the certificate chain of the in-memory certificate used by Envoy proxy shows the Issuer Organization (`O`) as `cert-manager` and common name (`CN`) as `istio-ca`. The Issuer should match the intermediate CA verified earlier.

```bash
istioctl proxy-config secret $(kubectl get pods -n $NAMESPACE -o jsonpath='{.items..metadata.name}' --selector app=$APP) -n $NAMESPACE -o json \
  | jq -r '.dynamicActiveSecrets[0].secret.tlsCertificate.certificateChain.inlineBytes' \
  | base64 --decode \
  | openssl x509 -text -noout
```

The output should be similar to below snippet.

```
Certificate:
    Data:
        ...
        Signature Algorithm: sha256WithRSAEncryption
        Issuer: O = cert-manager, CN = istio-ca
        ...
        X509v3 extensions:
            X509v3 Extended Key Usage: 
                TLS Web Client Authentication, TLS Web Server Authentication
            X509v3 Basic Constraints: critical
                CA:FALSE
            ...
            X509v3 Subject Alternative Name: 
                URI:spiffe://cluster.local/ns/workshop/sa/frontend-sa
    Signature Algorithm: sha256WithRSAEncryption
    ...
```

## Mutual TLS Enforcement Modes

This section will demonstrate the steps needed to validate and enforce Mutual Transport Layer Security (mTLS) for peer authentication between workloads.

By default, Istio will use mTLS for all workloads with proxies configured, however it will also allow plain text.  When the X-Forwarded-Client-Cert header is there, Istio will use mTLS, and when it is missing, it implies that the requests are in plain text.

![Sidecar mTLS connections](/images/04-peer-authentication-mtls-sidecar-connections.png)


Verify if mTLS is in Permissive mode (uses mTLS when available but allows plain text) or Strict mode (mTLS required). Note the value for "Workload mTLS mode" should show `PERMISSIVE`.

```bash
istioctl x describe pod $(kubectl get pods -n $NAMESPACE -o jsonpath='{.items..metadata.name}' --selector app=$APP).workshop
```

The output should look similar to the below sample output.

```
Pod: frontend-78f696695b-6txvg.workshop
   Pod Revision: default
   Pod Ports: 9000 (frontend), 15090 (istio-proxy)
--------------------
Service: frontend.workshop
   Port: http 9000/HTTP targets pod port 9000
--------------------
Effective PeerAuthentication:
   Workload mTLS mode: PERMISSIVE
Skipping Gateway information (no ingress gateway pods)
```

Open the Kiali dashboard.

```bash
istioctl dashboard kiali
```

Verify mTLS status in Kiali by checking the tooltip for the lock icon in the masthead.

![Kiali mast head lock tooltip for mesh wide auto mTLS](/images/04-kiali-mast-head-lock-auto-mtls.png)


If we want to force mTLS for all traffic, then we must enable STRICT mode.  Run the following command to force mTLS everywhere Istio is running.

```bash
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: "default"
  namespace: "istio-system"
spec:
  mtls:
    mode: STRICT
EOF
```

Verify that the workload mTLS mode shows `STRICT`.

```bash
istioctl x describe pod $(kubectl get pods -n $NAMESPACE -o jsonpath='{.items..metadata.name}' --selector app=$APP).workshop
```

The output should look similar to the below sample output.

```
Pod: frontend-78f696695b-6txvg.workshop
   Pod Revision: default
   Pod Ports: 9000 (frontend), 15090 (istio-proxy)
--------------------
Service: frontend.workshop
   Port: http 9000/HTTP targets pod port 9000
--------------------
Effective PeerAuthentication:
   Workload mTLS mode: STRICT
Applied PeerAuthentication:
   default.istio-system
Skipping Gateway information (no ingress gateway pods)
```

You can also check this by hovering your mouse over the Lock icon in the Kiali banner, which should now look like this:

![Kiali mast head lock tooltip for mesh wide strict mTLS](/images/04-kiali-mast-head-lock-default-strict-mode.png)


## Validation

Next we will run curl commands from another pod to test and verify that mTLS is enabled. While we already confirmed that configuration with the `istioctl` command, we need to look at debug logs to confirm that everything is working as expected. First we need to determine which pods are running so we know what to test. We'll try the frontend pod, where we will need both the pod name as well as the corresponding Istio sidecar. Let's get the full name of the pod, so we can enable debug logs on it. Note that your pod name will be different from mine.

Let's use the `istioctl` command to enable debug logs for the frontend pod.

```bash
istioctl pc log $(kubectl get pods -n $NAMESPACE -o jsonpath='{.items..metadata.name}' --selector app=$APP).workshop --level debug
```

Next, lets find the specific service we want to test, in this case, frontend.

```bash
kubectl get svc/frontend -n workshop
```

The output should look similar to below output. Note the service cluster IP in the output.

```
NAME       TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
frontend   ClusterIP   172.20.207.162   <none>        9000/TCP   27m
```

Now run a pod with curl to try and reach the `frontend` service.

```
kubectl run -i --tty curler --image=public.ecr.aws/k8m1l3p1/alpine/curler:latest --rm
```

Send a request to port 9000, which should get rejected as we don't have the proper certificate to authenticate to mTLS. Note that the IP address that it resolves to should be the same as what we saw before.

```bash
curl -v frontend.workshop.svc.cluster.local:9000
```

The output should be similar to the sample output below.

```
*   Trying 172.20.207.162:9000...
* Connected to frontend.workshop.svc.cluster.local (172.20.207.162) port 9000 (#0)
> GET / HTTP/1.1
> Host: frontend.workshop.svc.cluster.local:9000
> User-Agent: curl/7.77.0
> Accept: */*
> 
* Recv failure: Connection reset by peer
* Closing connection 0
curl: (56) Recv failure: Connection reset by peer
```

Terminate the container shell session.

Next, search the proxy debug log to verify that tls mode (`socket tlsMode-istio`) has been selected for proxy connections to the workload pods.

```bash
kubectl logs $(kubectl get pods -n $NAMESPACE -o jsonpath='{.items..metadata.name}' --selector app=$APP) -n workshop -c istio-proxy \
  | grep 'tlsMode.*:[359]000'
```

There should be matches similar to below snippet.

```
2024-04-17T17:38:00.214249Z     debug   envoy upstream external/envoy/source/common/upstream/upstream_impl.cc:426       transport socket match, socket tlsMode-istio selected for host with address 10.0.8.17:3000      thread=15
2024-04-17T17:38:00.214285Z     debug   envoy upstream external/envoy/source/common/upstream/upstream_impl.cc:426       transport socket match, socket tlsMode-istio selected for host with address 10.0.41.45:3000     thread=15
2024-04-17T17:38:00.214752Z     debug   envoy upstream external/envoy/source/common/upstream/upstream_impl.cc:426       transport socket match, socket tlsMode-istio selected for host with address 10.0.37.163:5000    thread=15
2024-04-17T17:38:00.215299Z     debug   envoy upstream external/envoy/source/common/upstream/upstream_impl.cc:426       transport socket match, socket tlsMode-disabled selected for host with address 10.0.41.134:3000 thread=15
2024-04-17T17:38:00.215464Z     debug   envoy upstream external/envoy/source/common/upstream/upstream_impl.cc:426       transport socket match, socket tlsMode-istio selected for host with address 10.0.43.244:9000    thread=15
```

Verify the pod IPs.

```bash
kubectl get pods -n $NAMESPACE -o custom-columns='NAME:metadata.name,PodIP:status.podIP'
```

The output should be similar to the below sample output.

```
NAME                              PodIP
catalogdetail-5896fff6b8-gqp5p    10.0.8.17
catalogdetail2-7d7d5cd48b-qw2dw   10.0.41.45
frontend-78f696695b-6txvg         10.0.43.244
productcatalog-64848f7996-62r74   10.0.37.163
```

### Validate Ingress Gateway TLS settings

Patch the application gateway definition to add a server route for HTTPS traffic on port 443.

```bash
kubectl patch gateway/productapp-gateway \
  -n workshop \
  --type=json \
  --patch='[{"op":"add","path":"/spec/servers/-","value":{"hosts":["*"],"port":{"name":"https","number":443,"protocol":"HTTP"}}}]'
```

The output should be similar to below sample.

```
gateway.networking.istio.io/productapp-gateway patched
```

Verify that the gateway is responding to HTTPS traffic using the exported PEM encoded CA certificate file from Private CA in the local directory.

```bash
ISTIO_INGRESS_URL=$(kubectl get service/istio-ingress -n istio-ingress -o json | jq -r '.status.loadBalancer.ingress[0].hostname')
curl --cacert ca-cert.pem https://$ISTIO_INGRESS_URL -s -o /dev/null -w "HTTP Response: %{http_code}\n"
```

The output should look similar to the sample output below.

```
HTTP Response: 200
```

Run a load test against the ingress gateway.

```bash
siege https://$ISTIO_INGRESS_URL -c 5 -d 10 -t 2M
```

Check the status of each connection in Kiali. Navigate to the Graph tab and enable Security in the Display menu. Then you will see a Lock icon to show where mTLS encryption is happening in the traffic flow graph.

![Application graph with auto mTLS](/images/04-kiali-auto-mtls-application-graph.png)

## Clean up

Clean up the resources set up in this section.

```bash
# Remove the patch for HTTPS route from application gateway resource
kubectl patch gateway/productapp-gateway \
  -n workshop \
  --type=json \
  --patch='[{"op":"remove","path":"/spec/servers/1"}]'

# Clean up the resources created by terraform for peer authentication
cd ../04-security
terraform destroy -target='module.setup_peer_authentication' -auto-approve
unset TF_VAR_aws_privateca_arn

# Restore base istio installation
cd ../../../terraform-aws-eks-blueprints/patterns/istio
terraform apply -auto-approve
kubectl rollout restart deployment istio-ingress -n istio-ingress
for ADDON in kiali jaeger prometheus grafana
do
    ADDON_URL="https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/$ADDON.yaml"
    kubectl apply -f $ADDON_URL
done

# Restart the deployments
kubectl rollout restart deployment/frontend -n workshop
kubectl rollout restart deployment/productcatalog -n workshop
kubectl rollout restart deployment/catalogdetail -n workshop
kubectl rollout restart deployment/catalogdetail2 -n workshop
```