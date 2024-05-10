# Module 3 - Securing Inngress and Egress traffic

This module shows the ingress and egress traffic to the mesh can be controlled and secured. The module is split into two sub modules one for ingress and other for egress.

1. [Secure Ingress](#control-ingress)
2. [Secure Egress](#control-egress)

## Prerequisites:
- [Module 1 - Getting Started](../01-getting-started/)

## Securing ingress traffic

 One of the key components of Istio is its ingress gateway, which serves as the entry point for incoming traffic into the service mesh. (TBD - add more details on ingress gateway and their importance before this sentence)

When it comes to securing the transport layer using Transport Layer Security (TLS) with Istio Ingress, there are two main approaches:

1. TLS Termination at Ingress Gateway: In this approach traffic is encrypted using TLS till ingress gateway. Ingress gateway can terminate TLS connections from external client and forward the traffic the traffic to component services within the mesh.  

2. Istio supports mutual TLS authentication, which ensures that both the client and the server authenticate each other using certificates. With mTLS enabled, communication between services within the mesh is encrypted and authenticated, providing an additional layer of security.


### Securing ingress traffic with TLS

To secure ingress traffic using TLS, we need to generate certficates and share the certificates keys with Ingress gateway through a K8s secret. Ingress gateway will use the shared certificate keys to establish TLS session with the client and allow for secure communication between the client and the services behind the ingress gateway in the mesh. A key consideration is that the TLS connection will be terminated at the Ingress gateway and further encryption of the traffic will depend on the traffic encryption policy within the mesh.

For this blog, we will use self signed certificates but for your production workloads it is recommend to use certificates from trusted CAs like AWS Certificate Manager.

1. Let us create the self signed certificates and import them to AWS Certificate Manager (ACM). To do this, we have use the terraform template defined below and apply it to create the certificate resources

```sh
cd secure-ingress-tls
terraform init
terraform plan 
terraform apply -auto-approve
```

2. Now you should be able to see certificate and key generated in the 'certs' directory and certificate material imported to ACM.
```sh
ls certs
istio-tls-root-cert.cert        istio-tls-root-private-key.key
```
```sh
export CERT_ARN=$(terraform output | cut -d '=' -f 2 | tr -d '"' | tr -d ' ')
aws acm describe-certificate --certificate-arn $CERT_ARN
```

3. The next step is to create an ingress gateway that will allow only TLS traffic from external sources through a network load balancer to the gateway. 

To support this configuration, we have to customize the ingress gateway pods to expose only ports 443 and 15020, configure the NLB to expose only the 443 port to external clients, and configure the 15020 port for performing  health checks on the ingress gateway pods. We then need to configure the NLB and the ingress gateway pods to use the certificate we generated in the last step. 

To configure the NLB with to use certificate we use the "service.beta.kubernetes.io/aws-load-balancer-ssl-cert" annotation as part of the ingress gateway service setup to refer the certificate.

For ingress pods, we will need to create Kubernetes TLS secret and provide it as part of the Istio Gateway object's TLS configuration.

```sh
kubectl create -n istio-ingress secret tls istio-tls-credential --key=certs/istio-tls-root-private-key.key --cert=certs/istio-tls-root-cert.cert
cd helm
helm install --set certARN=$CERT_ARN istio-tls-ingress-nlb . 
```

Test the ingress routing

```sh
export URL=$(k describe svc istio-ingressgateway-tls -n istio-ingress | grep -i 'LoadBalancer Ingress:' | cut -d ':' -f 2 | tr -d ' ')
curl  -o /dev/null -I -w "%{http_code}" https://${URL}/ --cacert ../certs/istio-tls-root-cert.cert
```

clean up
```sh
helm uninstall istio-tls-ingress-nlb
cd ..
terraform destroy --auto-approve
cd ..
kubectl delete secret istio-tls-credential  -n istio-ingress
```

### Securing ingress traffic with mTLS

configure mtls 

a. create certificate bundle from the client certificates
b. configure the certificate bundle to the ingress gateway for the clients 

```sh
cd controll-ingress-mTLS-auth
terraform init
terraform plan 
terraform apply -auto-approve
```

```sh
kubectl create -n istio-ingress secret generic istio-mtls-credential --from-file=tls.key=certs/istio-mtls-root-private-key.key --from-file=tls.crt=certs/istio-mtls-root-cert.cert --from-file=ca.crt=certs/client-1-mtls-root-cert.cert
cd helm
helm install istio-mtls-ingress-nlb . 
```

Test the ingress routing

```sh
export URL=$(kubectl get svc istio-ingressgateway-mtls -n istio-ingress -o json | jq -r '.status.loadBalancer.ingress[].hostname')
curl -o /dev/null -I -w "%{http_code}" https://${URL}/ --cacert ../certs/istio-mtls-root-cert.cert --key ../certs/client-1-mtls-root-private-key.key --cert ../certs/client-1-mtls-root-cert.cert

curl -o /dev/null -I -w "%{http_code}" https://${URL}/ --cacert ../certs/istio-mtls-root-cert.cert --key ../certs/client-2-mtls-root-private-key.key --cert ../certs/client-2-mtls-root-cert.cert
```

clean up
```sh
helm uninstall istio-mtls-ingress-nlb
cd ..
terraform destroy --auto-approve
kubectl delete secret istio-mtls-credential  -n istio-ingress
cd ..
```
### Controlling ingress traffic with mTLS authorization

### Using application load balancer to offload mTLS validation to the load balancer

configure mtls  with alb in proxy mode

a. create trust bundle from the client certificates
b. configure the trus bundle to the ingress gateway for the clients 

```sh
cd offload-mTLS-auth-ALB
terraform init
terraform plan 
terraform apply -auto-approve
```

```sh
aws s3 mb s3://mahali-istio-alb-truststore
#aws s3api put-bucket-versioning --bucket mahali-istio-alb-truststore  --versioning-configuration Status=Enabled 
aws s3 cp certs/client-1-mtls-ca-cert.cert s3://mahali-istio-alb-truststore/trust-store/client-1-mtls-ca-cert.cert
export trustStoreARN=$(aws elbv2 create-trust-store --name istio-alb-truststore --ca-certificates-bundle-s3-bucket mahali-istio-alb-truststore --ca-certificates-bundle-s3-key trust-store/client-1-mtls-ca-cert.cert | jq -r '.TrustStores[].TrustStoreArn')
```

```sh
export CERT_ARN=$(terraform output | cut -d '=' -f 2 | tr -d '"' | tr -d ' ')
aws acm describe-certificate --certificate-arn $CERT_ARN
kubectl create -n istio-ingress secret tls istio-tls-credential --key=certs/istio-mtls-root-private-key.key --cert=certs/istio-mtls-root-cert.cert
```

```sh
cd helm
helm install --set certARN=$CERT_ARN  --set trustStoreARN=$trustStoreARN istio-mtls-ingress-alb . 
```

Test the ingress routing

```sh
export URL=$(kubectl get ingress istio-ingress-tls -n istio-ingress -o json | jq -r '.status.loadBalancer.ingress[].hostname')
curl -o /dev/null -I -w "%{http_code}" https://${URL}/ --cacert ../certs/istio-mtls-root-cert.cert --key ../certs/client-1-mtls-private-key.key --cert ../certs/client-1-mtls-cert.cert 

```

clean up
```sh
helm uninstall istio-mtls-ingress-alb
cd ..
terraform destroy --auto-approve
kubectl delete secret istio-tls-credential  -n istio-ingress
aws elbv2 delete-trust-store --trust-store-arn $trustStoreARN
aws s3 rm s3://mahali-istio-alb-truststore/trust-store/client-1-mtls-ca-cert.cert
aws s3 rb s3://mahali-istio-alb-truststore 
cd ..
```

### Securing egress traffic 

a. Passthrough mode

b. mTLS and TLS orgination at egress gateway