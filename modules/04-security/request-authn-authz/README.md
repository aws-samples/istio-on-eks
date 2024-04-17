# Security - Request Authentication & Authorization

This sub-module focuses on request authentication and authorization flows.
It is further split into two more sub-modules for request authentication and external authorization using OPA.

## Setup

Both request authentication and OPA based external authorization sub-modules require Keycloak for application user management.

Apply the terraform module to prepare for the request authentication and authorization sub-modules.

```bash
terraform apply -target='module.setup_request_authn_authz' -auto-approve
```

This setup module installs Keycloak and creates the following Keycloak resources.

| Resource Type | Name | Purpose |
|---------------|------|---------|
| Realm | `workshop` | A container for users, roles and OIDC application client settings. |
| Client | `productapp` | OIDC application client. |
| Roles | `-` | [See Application Roles](#application-roles) |
| Users | `-` | [See Application Users](#application-users) |

#### Application Roles
The following application roles are created in `workshop` realm.

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

## Scripts

The following scripts have been provided to interact with Keycloak and configure Istio request authentication and authorization resources from the terminal.

| Name | Purpose | Arguments |
|------|---------|-----------|
| [`scripts/helpers.sh`](/modules/04-security/scripts/helpers.sh) | Contains helper functions to generate and inspect access tokens, apply authentication and authorization policies on ingress gateway, and print Keycloak admin console access information. | [See arguments](#script-arguments-helperssh) |

### Script Arguments: `helpers.sh`

Following table lists the arguments of `helpers.sh` script.

| Short Form | Long Form | Value Type | Required | Default | Description |
|------------|-----------|------------|----------|---------|-------------|
| `-a` | `--admin` | `-` | No | `-` | Print Keycloak admin password. Mutually exclusive with `-c`\|`--console`, `-g`\|`--generate`, `-i`\|`--inspect`, `--authn` and `--authz`. |
| `-c` | `--console` | `-` | No | `-` | Print Keycloak console URL. Mutually exclusive with `-a`\|`--admin`, `-g`\|`--generate`, `-i`\|`--inspect`, `--authn` and `--authz`. |
| `-g` | `--generate` | `-` | No | `-` | Generate access token for application user (requires `-u\|--user`). Mutually exclusive with `-a`\|`--admin`, `-c`\|`--console`, `-i`\|`--inspect`, `--authn` and `--authz`. |
| `-u` | `--user` | `string` | Required when `-g\|--generate` is set | `-` | Application username. |
| `-i` | `--inspect` | `-` | No | `-` | Inspect access token (requires `-t`\|`--token`). Mutually exclusive with `-a`\|`--admin`, `-c`\|`--console`, `-g`\|`--generate`, `--authn` and `--authz`. |
| `-t` | `--token` | `string` | Required when `-i`\|`--inspect` is set | `-` | Access token. |
| `-` | `--authn` | `-` | `-` | `-` | Apply `RequestAuthentication` manifest. Mutually exclusive with `-a`\|`--admin`, `-c`\|`--console`, `-g`\|`--generate`, `-i`\|`--inspect` and `--authz`. |
| `-` | `--authz` | `-` | `-` | `-` | Apply `AuthorizationPolicy` manifest. Mutually exclusive with `-a`\|`--admin`, `-c`\|`--console`, `-g`\|`--generate`, `-i`\|`--inspect` and `--authn`. |
| `-n` | `--keycloak-namespace` | `string` | No | `keycloak` | Namespace for keycloak |
| `-r` | `--keycloak-realm` | `string` | No | `istio` | Keycloak realm for istio |
| `-h` | `--help` | `-` | No | `-` | Show help message |
| `-v` | `--verbose` | `-` | No | `-` | Generate verbose output |


Below are some examples of using the helper script to perform various actions related to configuring Istio request authentication and authorization.

### Examples:
---

| Action description | Script invocation |
|--------------------|-------------------|
| Generate access token for application user `alice` | `scripts/helpers.sh -g -u alice` |
| Inspect generated access token | `scripts/helpers.sh -i -t {TOKEN}` |
| Apply `RequestAuthentication` manifest | `scripts/helpers.sh --authn` |
| Apply `AuthorizationPolicy` manifest | `scripts/helpers.sh --authz` |
| Print Keycloak admin console URL | `scripts/helpers.sh -c` |
| Print Keycloak admin user password | `scripts/helpers.sh -a` |

**Note:** Remember to set the correct AWS region in the terminal window before invoking the script.
For example, in the bash terminal window execute the following. Make sure the region is the one where the terraform stack has created the keycloak resources.

```bash
export AWS_REGION=us-west-2
```

Once the keycloak resources are setup successfully move on to the sub-modules.

## Clean up

Clean up the resources set up in this section.

```bash
terraform destroy -target='module.setup_request_authn_authz' -auto-approve
```

## 🧱 Sub Modules

### [1. Request Authentication](/modules/04-security/request-authn-authz/request-authentication/README.md)
### [2. OPA based External Authorization](/modules/04-security/request-authn-authz/opa-external-authorization/README.md)