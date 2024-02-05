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

## Scripts

To make it easier to work with Keycloak the following scripts have been provided.

| Name | Purpose | Arguments |
|------|---------|-----------|
| [`04-keycloak-setup.sh`](/bin/04-keycloak-setup.sh) | Installs Keycloak in the Amazon EKS cluster and provisions a new realm with users, roles and OIDC client for `productapp` application. Saves Keycloak admin user and application user credentials in AWS Secrets Manager. Uses `external-secrets` to load the admin credential for Keycloak. | [See arguments](#script-arguments-04-keycloak-setupsh) |
| [`04-keycloak-cleanup.sh`](/bin/04-keycloak-cleanup.sh) | Uninstalls Keycloak and cleans up all the related Kubernetes and AWS resources. | [See arguments](#script-arguments-04-keycloak-cleanupsh) |
| [`04-keycloak-helpers.sh`](/bin/04-keycloak-helpers.sh) | Contains helper functions to generate and introspect access tokens, apply authentication and authorization policies on ingress gat4eway, and print Keycloak admin console access information. | [See arguments](#script-arguments-04-keycloak-helperssh) |

### Script Arguments: `04-keycloak-setup.sh`

Following table lists the arguments of `04-keycloak-setup.sh` script.

| Short Form | Long Form | Value Type | Required | Default | Description |
|------------|-----------|------------|----------|---------|-------------|
| `-a` | `--account_id` | `string` | No | Inferred from `ACCOUNT_ID` environment variable or else by calling STS `GetCallerIdentity` | AWS account id |
| `-c` | `--cluster-name` | `string` | Yes | `-` | Amazon EKS cluster name |
| `-n` | `--keycloak-namespace` | `string` | No | `keycloak` | Namespace for keycloak |
| `-r` | `--keycloak-realm` | `string` | No | `istio` | Keycloak realm for istio |
| `-h` | `--help` | `-` | No | `-` | Show help message |

### Script Arguments: `04-keycloak-cleanup.sh`

Following table lists the arguments of `04-keycloak-cleanup.sh` script.

| Short Form | Long Form | Value Type | Required | Default | Description |
|------------|-----------|------------|----------|---------|-------------|
| `-a` | `--account_id` | `string` | No | Inferred from `ACCOUNT_ID` environment variable or else by calling STS `GetCallerIdentity` | AWS account id |
| `-c` | `--cluster-name` | `string` | Yes | `-` | Amazon EKS cluster name |
| `-n` | `--keycloak-namespace` | `string` | No | `keycloak` | Namespace for keycloak |
| `-h` | `--help` | `-` | No | `-` | Show help message |

### Script Arguments: `04-keycloak-helpers.sh`

Following table lists the arguments of `04-keycloak-helpers.sh` script.

| Short Form | Long Form | Value Type | Required | Default | Description |
|------------|-----------|------------|----------|---------|-------------|
| `-a` | `--admin` | `-` | No | `-` | Print Keycloak admin password. Mutually exclusive with `-c`\|`--console`, `-g`\|`--generate`, `-i`\|`--introspect`, `--authn` and `--authz`. |
| `-c` | `--console` | `-` | No | `-` | Print Keycloak console URL. Mutually exclusive with `-a`\|`--admin`, `-g`\|`--generate`, `-i`\|`--introspect`, `--authn` and `--authz`. |
| `-g` | `--generate` | `-` | No | `-` | Generate access token for application user (requires `-u\|--user`). Mutually exclusive with `-a`\|`--admin`, `-c`\|`--console`, `-i`\|`--introspect`, `--authn` and `--authz`. |
| `-u` | `--user` | `string` | Required when `-g\|--generate` is set | `-` | Application username. |
| `-i` | `--introspect` | `-` | No | `-` | Introspect access token (requires `-t`\|`--token`). Mutually exclusive with `-a`\|`--admin`, `-c`\|`--console`, `-g`\|`--generate`, `--authn` and `--authz`. |
| `-t` | `--token` | `string` | Required when `-i`\|`--introspect` is set | `-` | Access token. |
| `-` | `--authn` | `-` | `-` | `-` | Apply `RequestAuthentication` manifest. Mutually exclusive with `-a`\|`--admin`, `-c`\|`--console`, `-g`\|`--generate`, `-i`\|`--introspect` and `--authz`. |
| `-` | `--authz` | `-` | `-` | `-` | Apply `AuthorizationPolicy` manifest. Mutually exclusive with `-a`\|`--admin`, `-c`\|`--console`, `-g`\|`--generate`, `-i`\|`--introspect` and `--authn`. |
| `-n` | `--keycloak-namespace` | `string` | No | `keycloak` | Namespace for keycloak |
| `-r` | `--keycloak-realm` | `string` | No | `istio` | Keycloak realm for istio |
| `-h` | `--help` | `-` | No | `-` | Show help message |

## Deploy

### Install Keycloak

Run the `04-keycloak-setup.sh` script to install and setup Keycloak.

```bash
../../bin/04-keycloak-setup.sh -c istio
```

It takes a few minutes to finish the setup. On successful completion the output should look similar to the sample output below.

```
...
Target health is healthy.

Keycloak setup done.

--------------------------------------
Next Steps
--------------------------------------
This setup script has created a new realm in Keycloak for Istio authentication.

The realm contains the following resources:
 - three application roles,
 - three application users that are assigned to each of the roles respectively and
 - an OIDC client for 'productapp' application.

The user and role assignments are shown below:
+ ---------- + ---------- +
| User       | Role       |
+ ---------- + ---------- +
| alice      | guest      |
| bob        | admin      |
| charlie    | other      |
+ ---------- + ---------- +

A helper script ('bin/04-keycloak-helpers.sh') is provided to easily interact with Keycloak and configure Istio request authentication resources.
Below are some examples of using the helper script to perform various actions related to configuring Istio request authentication.

Examples:
---------
 - Generate access token for application user 'alice':
   $ bin/04-keycloak-helpers.sh -g -u alice

 - Introspect generated access token:
   $ bin/04-keycloak-helpers.sh -i -t <TOKEN>

 - Apply RequestAuthentication manifest:
   $ bin/04-keycloak-helpers.sh --authn

 - Apply AuthorizationPolicy manifest:
   $ bin/04-keycloak-helpers.sh --authz

 - Print Keycloak admin console URL:
   $ bin/04-keycloak-helpers.sh -c

 - Print Keycloak admin user password:
   $ bin/04-keycloak-helpers.sh -a

Clean up:
---------
Once done experimenting with Keycloak integration use the provided clean up script ('bin/04-keycloak-cleanup.sh') to clean up all the Kubernetes and AWS resources created by this script.
--------------------------------------

```

The setup script creates the following Keycloak resources.

| Resource Type | Name | Purpose |
|---------------|------|---------|
| Realm | `istio` | A container for users, roles and OIDC application client settings. |
| Client | `productapp` | OIDC application client. |
| Roles | `-` | [See Application Roles](#application-roles) |
| Users | `-` | [See Application Users](#application-users) |

#### Application Roles
The following application roles are created in `istio` realm.

| Role | Purpose |
|------|---------------|
| `guest` | Views products list. |
| `admin` | Views and modifies products list. |
| `other` | `-` |

#### Application Users
The following application users and the corresponding role assignments are created in `istio` realm.

| User | Role |
|------|------|
| `alice` | `guest` |
| `bob` | `admin` |
| `charlie` | `other` |

### Enable request authentication

The [request authentication template](./ingress-requestauthentication-template.yaml) contains `ISSUER` and `JWKS_URI` placeholders that are replaced by the helper script. Apply request authentication policy to the ingress gateway.

```bash
../../bin/04-keycloak-helpers.sh --authn
```

The output should look similar to the sample output below.

```
requestauthentication.security.istio.io/istio-ingress created
```

Inspect the applied `RequestAuthentication` object.

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
  Creation Timestamp:  2024-02-04T16:21:55Z
  Generation:          1
  Resource Version:    12804
  UID:                 17e9b3ca-3220-41ac-a821-cd02c160b100
Spec:
  Jwt Rules:
    Audiences:
      productapp
    Forward Original Token:  true
    Issuer:                  http://k8s-keycloak-keycloak-....elb.us-west-2.amazonaws.com/realms/istio
    Jwks Uri:                http://k8s-keycloak-keycloak-....elb.us-west-2.amazonaws.com/realms/istio/protocol/openid-connect/certs
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

```bash
export INGRESS_HOST=$(kubectl get svc istio-ingress -n istio-ingress -o jsonpath='{.status.loadBalancer.ingress[*].hostname}')
```

### Generate access tokens

Generate a token for user `alice`.

```bash
TOKEN=$(../../bin/04-keycloak-helpers.sh -g -u alice)
```

Introspect the generated access token using the helper script.

```bash
../../bin/04-keycloak-helpers.sh -i -t $TOKEN
```

The decoded JWT output should look similar to below.

```json
Decoded JWT
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "DDVGsPja_2E3nrNLt9Fch5wRNQ-anTK4C63ygKSlPq8"
}
{
  "exp": 1707067494,
  "iat": 1707067194,
  "jti": "734054e7-942e-4de9-9cc6-660cab0f1cbf",
  "iss": "http://k8s-keycloak-keycloak-....elb.us-west-2.amazonaws.com/realms/istio",
  "aud": "productapp",
  "sub": "alice@example.com",
  "typ": "Bearer",
  "azp": "productapp",
  "session_state": "5add6301-31e3-4f42-bc0b-44dcbba444b7",
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
  "sid": "5add6301-31e3-4f42-bc0b-44dcbba444b7",
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

```bash
TOKEN=$(../../bin/04-keycloak-helpers.sh -g -u alice)
curl --header "Authorization: Bearer $TOKEN" "$INGRESS_HOST" -s -o /dev/null -w "HTTP Response: %{http_code}\n"
```

The output should look similar to the sample output below.

```
HTTP Response: 200
```

 If the output shows `HTTP Response: 401` then generate a new token and resend the request.

### Scenario: Request with invalid token should be rejected

Generate a bogus token and send a request to the application endpoint.

```bash
TOKEN=bogus
curl --header "Authorization: Bearer $TOKEN" "$INGRESS_HOST" -s -o /dev/null -w "HTTP Response: %{http_code}\n"
```

The output should look similar to the sample output below.

```
HTTP Response: 401
```

### Scenario: Request with no token should be allowed

Send a request to the application endpoint with no bearer token.

```bash
curl "$INGRESS_HOST" -s -o /dev/null -w "HTTP Response: %{http_code}\n"
```

The output should look similar to the sample output below.

```
HTTP Response: 200
```

## Deny requests with missing tokens

A [deny AuthorizationPolicy](./ingress-authorizationpolicy.yaml) is used to reject requests with missing JWT tokens. The policy rejects all requests to port `80` with missing `requestPrincipal` attribute which is only available for authenticated requests.

Apply the authorization policy.

```bash
../../bin/04-keycloak-helpers.sh --authz
```

The output should look similar to the sample output below.

```
authorizationpolicy.security.istio.io/istio-ingress created
```

View the authorization policy applied above.

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
  Creation Timestamp:  2024-02-04T19:28:26Z
  Generation:          1
  Resource Version:    67741
  UID:                 54862f98-49bf-4d4a-8176-19b24c1cc3d9
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
  Selector:
    Match Labels:
      Istio:  ingressgateway
Events:       <none>
```

Send another request to the application endpoint with no bearer token.

```bash
curl "$INGRESS_HOST" -s -o /dev/null -w "HTTP Response: %{http_code}\n"
```

The output should look similar to the sample output below.

```
HTTP Response: 403
```

## Clean up

Clean up the resources set up in this section.

```bash
# Delete the AuthorizationPolicy object
kubectl delete AuthorizationPolicy/istio-ingress -n istio-ingress
kubectl delete RequestAuthentication/istio-ingress -n istio-ingress

# Clean up the Keycloak resources
../../bin/04-keycloak-cleanup.sh -c istio
```
