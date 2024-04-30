# Security - Request Authentication

This section shows request authentication capabilities of Istio service-mesh on Amazon EKS using [Keycloak](https://www.keycloak.org/) as an [OpenID Connect (OIDC)](https://openid.net/developers/how-connect-works/) identity provider.

Istio can authenticate end-user requests by validating a [JSON Web Token (JWT)](https://jwt.io/) using 
either a custom authentication provider or any compliant OIDC provider like Keycloak. 

A [RequestAuthentication](https://istio.io/latest/docs/reference/config/security/request_authentication/) policy object is used to implement JWT based request authentication. A minimal policy object is made up of the following parts:

  * policy storage location which also determines the overall scope of the policy
  * workload selector to further restrict the scope of policies stored within non-root namespaces
  * [JWT rules](https://istio.io/latest/docs/reference/config/security/jwt/) to discover (default HTTP header `Authorization: Bearer <JWT>`) and validate JWTs in incoming requests and optionally mutate validated upstream requests

Requests that match the JWT validation rules are allowed to pass through to the destination application services.

![Request authentication flow with valid JWT](/images/04-request-authentication-1.png)

*Figure: Request authentication flow with valid JWT*

Requests that violate the JWT validation rules are automatically rejected by the Istio proxies.

![Request authentication flow with invalid JWT](/images/04-request-authentication-2.png)

*Figure: Request authentication flow with invalid JWT*

Istio's request authentication policies only match requests that contain a JWT for validation.
This means requests with missing JWTs will be allowed to pass through by the Istio proxies to the 
destination application services.

![Request authentication flow with no JWT](/images/04-request-authentication-3.png)

*Figure: Request authentication flow with no JWT*

To also reject requests with missing JWTs, the request authentication policies must be complemented with
[authorization policies](https://istio.io/latest/docs/ops/configuration/security/security-policy-examples/#require-mandatory-authorization-check-with-deny-policy) that expect authenticated claims like `requestPrincipal`, which is automatically 
constructed by Istio by concatenating the `iss` and `sub` claims from the validated JWT with a `/` 
separator, to be present in the request and deny all other requests.

![Request authentication and authorization flow with no JWT](/images/04-request-authentication-4.png)

*Figure: Request authentication and authorization flow with no JWT*

## Prerequisites

**Note:** Make sure that the required resources have been created following the [setup instructions](../README.md#setup).

## Deploy

### Enable request authentication

The [request authentication template](./ingress-requestauthentication-template.yaml) contains `ISSUER` and `JWKS_URI` placeholders that are replaced by the helper script. Apply request authentication policy to the ingress gateway.

**:hourglass_flowing_sand: Command Line Execution**

```bash
../scripts/helpers.sh --authn
```

The output should look similar to the sample output below.

```
requestauthentication.security.istio.io/istio-ingress created
```

Inspect the applied `RequestAuthentication` object.

**:hourglass_flowing_sand: Command Line Execution**

```bash
kubectl describe RequestAuthentication/istio-ingress -n istio-ingress 
```

The output should look similar to the sample output below.

```yaml
Name:         istio-ingress
Namespace:    istio-ingress
Labels:       <none>
Annotations:  <none>
API Version:  security.istio.io/v1
Kind:         RequestAuthentication
Metadata:
  Creation Timestamp:  2024-04-17T19:55:01Z
  Generation:          1
  Resource Version:    68767
  UID:                 24c32bb4-32b9-4c80-ac1f-c893f19c6bc5
Spec:
  Jwt Rules:
    Audiences:
      productapp
    Forward Original Token:  true
    Issuer:                  http://k8s-keycloak-keycloak-....elb.us-west-2.amazonaws.com/realms/workshop
    Jwks Uri:                http://k8s-keycloak-keycloak-....elb.us-west-2.amazonaws.com/realms/workshop/protocol/openid-connect/certs
  Selector:
    Match Labels:
      Istio:  ingressgateway
Events:       <none>
```

Note the fields under `Jwt Rules`. The `Audiences` field ensures the token is intended for the `productapp` application only.
The `Issuer` and `Jwks Uri` fields ensure the token is vended and signed by the right Keycloak instance. 
The `Forward Original Token` field ensures the original JWT is propagated to the upstream service.

## Validate

Export the ingress load balancer URL.

**:hourglass_flowing_sand: Command Line Execution**

```bash
export ISTIO_INGRESS_URL=$(kubectl get svc istio-ingress -n istio-ingress -o jsonpath='{.status.loadBalancer.ingress[*].hostname}')
```

### Generate access tokens

Generate a token for user `alice`.

**:hourglass_flowing_sand: Command Line Execution**

```bash
TOKEN=$(../scripts/helpers.sh -g -u alice)
```

Inspect the generated access token using the helper script.

**:hourglass_flowing_sand: Command Line Execution**

```bash
../scripts/helpers.sh -i -t $TOKEN
```

The decoded JWT output should look similar to below.

```json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "ZjoOwCVXlCzw7ng3pvEVEVQjAGH-_73z5Q5rR6EyN0I"
}
{
  "exp": 1713384107,
  "iat": 1713383807,
  "jti": "1155a781-7013-4b61-afda-bd9dc320299e",
  "iss": "http://k8s-keycloak-keycloak-....elb.us-west-2.amazonaws.com/realms/workshop",
  "aud": "productapp",
  "sub": "alice@example.com",
  "typ": "Bearer",
  "azp": "productapp",
  "session_state": "0921a569-d587-4378-827a-b404a62122b2",
  "acr": "1",
  "allowed-origins": [
    "/*"
  ],
  "realm_access": {
    "roles": [
      "guest"
    ]
  },
  "scope": "profile email",
  "sid": "0921a569-d587-4378-827a-b404a62122b2",
  "email_verified": true,
  "name": "Alice",
  "preferred_username": "alice",
  "given_name": "Alice",
  "email": "alice@example.com"
}
```

Note the values of the issuer (`iss`) and audience (`aud`) claims. These match those referred in the request authentication policy applied to the ingress gateway earlier. Also note the generated access tokens are valid for 5 minutes (validity in seconds = `exp` - `iat`).

### Scenario: Request with valid token should be successful

Send a request to the ingress endpoint setting the generated token in the authorization header.

**:hourglass_flowing_sand: Command Line Execution**

```bash
TOKEN=$(../scripts/helpers.sh -g -u alice)
curl --cacert ../lb_ingress_cert.pem --header "Authorization: Bearer $TOKEN" https://$ISTIO_INGRESS_URL -s -o /dev/null -w "HTTP Response: %{http_code}\n"
```

The output should look similar to the sample output below.

```
HTTP Response: 200
```

 If the output shows `HTTP Response: 401` then generate a new token and resend the request.

### Scenario: Request with invalid token should be rejected

Generate a bogus token and send a request to the application endpoint.

**:hourglass_flowing_sand: Command Line Execution**

```bash
TOKEN=bogus
curl --cacert ../lb_ingress_cert.pem --header "Authorization: Bearer $TOKEN" https://$ISTIO_INGRESS_URL -s -o /dev/null -w "HTTP Response: %{http_code}\n"
```

The output should look similar to the sample output below.

```
HTTP Response: 401
```

### Scenario: Request with no token should be allowed

Send a request to the application endpoint with no bearer token.

**:hourglass_flowing_sand: Command Line Execution**

```bash
curl --cacert ../lb_ingress_cert.pem https://$ISTIO_INGRESS_URL -s -o /dev/null -w "HTTP Response: %{http_code}\n"
```

The output should look similar to the sample output below.

```
HTTP Response: 200
```

## Deny requests with missing tokens

A [deny AuthorizationPolicy](./ingress-authorizationpolicy.yaml) is used to reject requests with missing JWT tokens. The policy rejects all requests to port `80` with missing `requestPrincipal` attribute which is only available for authenticated requests.

Apply the authorization policy.

**:hourglass_flowing_sand: Command Line Execution**

```bash
../scripts/helpers.sh --authz
```

The output should look similar to the sample output below.

```
authorizationpolicy.security.istio.io/istio-ingress created
```

View the authorization policy applied above.

**:hourglass_flowing_sand: Command Line Execution**

```bash
kubectl describe AuthorizationPolicy/istio-ingress -n istio-ingress
```

The output should look similar to the sample output below.

```yaml
Name:         istio-ingress
Namespace:    istio-ingress
Labels:       <none>
Annotations:  <none>
API Version:  security.istio.io/v1
Kind:         AuthorizationPolicy
Metadata:
  Creation Timestamp:  2024-04-22T13:05:34Z
  Generation:          2
  Resource Version:    62695
  UID:                 6b785539-2e4b-4b9b-b890-61132c7b7dd3
Spec:
  Action:  DENY
  Rules:
    From:
      Source:
        Not Request Principals:
          *
    To:
      Operation:
        Ports:
          80
          443
  Selector:
    Match Labels:
      Istio:  ingressgateway
Events:       <none>
```

Note that both ports 80 and 443 are referred in the `AuthorizationPolicy`

Send another request to the application endpoint with no bearer token.

**:hourglass_flowing_sand: Command Line Execution**

```bash
curl --cacert ../lb_ingress_cert.pem https://$ISTIO_INGRESS_URL -s -o /dev/null -w "HTTP Response: %{http_code}\n"
```

The output should look similar to the sample output below.

```
HTTP Response: 403
```

Congratulations!!! You've now successfully validated request authentication setup in Istio on Amazon EKS. :tada:

You can either move on to the other sub-modules or if you're done with this module then refer to [Clean up](../README.md#clean-up) to clean up all the resources provisioned in this module.