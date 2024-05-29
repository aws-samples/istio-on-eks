# Ingress Gateway Certificate Management

Typically, to protect publicly accessible `istio-ingress` service load balancer endpoints on the internet, you will issue certificates from a well-known, trusted third party root CA or an intermediate CA and associate it with the load balancer HTTPS listener. Refer to [Issuing and managing certificates using AWS Certificate Manager](https://docs.aws.amazon.com/acm/latest/userguide/gs.html) for issuing or importing certificates. Refer to [AWS Load Balancer Controller service annotations TLS](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.7/guide/service/annotations/#tls) section for details on how to associate ACM certificates with service load balancer listeners using service annotations.

You can also import certificates issued by AWS Private CA configured in standard mode into ACM. AWS Private CA configured in short-lived mode is not supported. However, for this module a self-signed certificate is used for the internet facing `istio-ingress` load balancer endpoint to avoid creating another Private CA resource. The self-signed certificate has been generated and imported into ACM. The generated PEM-encoded self-signed certificate (`lb_ingress_cert.pem`) is also exported in the module directory (`04-security`).

As part of the setup process, the imported self-signed ACM certificate is associated with the HTTPS listener of the `istio-ingress` load balancer resource using annotations on the `istio-ingress` service.

![Istio Ingress Gateway drawio](https://github.com/aws-samples/istio-on-eks/assets/71530829/08a1fa31-a61e-475c-b1be-ebc7deaa95d9)

*Figure: Istio Ingress Gateway using ACM
<br/><br/>


## Prerequisites

**Note:** Make sure that the required resources have been created following the [setup instructions](../README.md#setup).

**:warning: WARN:** Some of the commands shown in this section refer to relative file paths that assume the current directory is `istio-on-eks/modules/04-security/terraform`. If your current directory does not match this path, then either change to the above directory to execute the commands or if executing from any other directory, then adjust the file paths like `../scripts/helpers.sh` and `../lb_ingress_cert.pem` accordingly.


## Verify Setup

**Describe the service to verify the annotations**

```bash
kubectl get svc/istio-ingress -n istio-ingress -o jsonpath='{.metadata.annotations}' | jq -r
```

The output should look similar to the below sample output.

```json
{
  "meta.helm.sh/release-name": "istio-ingress",
  "meta.helm.sh/release-namespace": "istio-ingress",
  "service.beta.kubernetes.io/aws-load-balancer-attributes": "load_balancing.cross_zone.enabled=true",
  "service.beta.kubernetes.io/aws-load-balancer-backend-protocol": "tcp",
  "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type": "ip",
  "service.beta.kubernetes.io/aws-load-balancer-scheme": "internet-facing",
  "service.beta.kubernetes.io/aws-load-balancer-ssl-cert": "arn:aws:acm:REGION:ACCOUNT_ID:certificate/CERT_ID",
  "service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy": "ELBSecurityPolicy-TLS13-1-2-2021-06",
  "service.beta.kubernetes.io/aws-load-balancer-ssl-ports": "https",
  "service.beta.kubernetes.io/aws-load-balancer-type": "external"
}
```

Note the below annotation values

| Annotation | Value |
|------------|-------|
| `service.beta.kubernetes.io/aws-load-balancer-ssl-cert` | ARN of imported self-signed ACM certificate |
| `service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy` | `ELBSecurityPolicy-TLS13-1-2-2021-06` |
| `service.beta.kubernetes.io/aws-load-balancer-ssl-ports` | `https` |

The application gateway definition is patched to add a server route for HTTPS traffic on port 443.

**Describe the `gateway` resource and verify that there are routes for port 80 and port 443 respectively**

```bash
kubectl get gateway/productapp-gateway -n workshop -o jsonpath='{.spec.servers}' | jq -r
```

The output should be similar to below sample.

```json
[
  {
    "hosts": [
      "*"
    ],
    "port": {
      "name": "http",
      "number": 80,
      "protocol": "HTTP"
    }
  },
  {
    "hosts": [
      "*"
    ],
    "port": {
      "name": "https",
      "number": 443,
      "protocol": "HTTP"
    }
  }
]
```

**Verify that the gateway is accepting HTTPS traffic and forwarding to the right application**

First export the ingress gateway load balancer endpoint.

```bash
ISTIO_INGRESS_URL=$(kubectl get service/istio-ingress -n istio-ingress -o json | jq -r '.status.loadBalancer.ingress[0].hostname')
```

Next, send a request to the ingress gateway load balancer endpoint using `curl` referring to the exported self-signed certificate using the `--cacert` flag for certificate verification.

```bash
curl --cacert ../lb_ingress_cert.pem https://$ISTIO_INGRESS_URL -s -o /dev/null -w "HTTP Response: %{http_code}\n"
```

The output should look similar to the sample output below.

```
HTTP Response: 200
```

**Run a load test against the ingress gateway, so that its easy to visual the traffic in Kiali**

```bash
siege https://$ISTIO_INGRESS_URL -c 5 -d 10 -t 2M
```

Check the status of each connection in Kiali. Navigate to the Graph tab and enable Security in the Display menu. Then you will see a Lock icon to show where mTLS encryption is happening in the traffic flow graph.

![Application graph with auto mTLS](/images/04-kiali-auto-mtls-application-graph.png)

Congratulations!!! You've now successfully validated ingress security in Istio on Amazon EKS. :tada:

You can either move on to the other sub-modules or if you're done with this module then refer to [Clean up](../README.md#clean-up) to clean up all the resources provisioned in this module.
