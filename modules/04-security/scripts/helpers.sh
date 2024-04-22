#!/bin/bash
#
# Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

#title           helpers.sh
#description     This script contains helper functions.
#author          Sourav Paul (@psour)
#contributors    @psour
#date            2024-04-12
#version         1.0
#usage           ./helpers.sh [-a|--admin] [-c|--console] [-g|--generate -u|--user <APP_USER>] [-i|--inspect -t|--token <TOKEN>] [-w|--wait-lb -l|--lb-arn-pattern <LB_ARN_PATTERN>] [--authn] [--authz] [-n|--keycloak-namespace <KEYCLOAK_NAMESPACE>] [-r|--keycloak-realm <KEYCLOAK_REALM>] [-h|--help] [-v|--verbose]
#==============================================================================

#### Resolve command line arguments
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--admin)
      PRINT_ADMIN_PASSWORD=YES
      shift # past argument
      ;;
    -c|--console)
      PRINT_ADMIN_CONSOLE_URL=YES
      shift # past argument
      ;;
    -g|--generate)
      GENERATE_TOKEN=YES
      shift # past argument
      ;;
    -u|--user)
      APP_USER="$2"
      shift # past argument
      shift # past value
      ;;
    -i|--inspect)
      INSPECT_TOKEN=YES
      shift # past argument
      ;;
    -t|--token)
      TOKEN="$2"
      shift # past argument
      shift # past value
      ;;
    --authn)
      APPLY_AUTHN=YES
      shift # past argument
      ;;
    --authz)
      APPLY_AUTHZ=YES
      shift # past argument
      ;;
    -n|--keycloak-namespace)
      KEYCLOAK_NAMESPACE="$2"
      shift # past argument
      shift # past value
      ;;
    -r|--keycloak-realm)
      KEYCLOAK_REALM="$2"
      shift # past argument
      shift # past value
      ;;
    -w|--wait-lb)
      WAIT_LB=YES
      shift # past argument
      ;;
    -l|--lb-arn-pattern)
      LB_ARN_PATTERN="$2"
      shift # past argument
      shift # past value
      ;;
    -h|--help)
      SHOW_HELP=YES
      shift # past argument
      ;;
    -v|--verbose)
      VERBOSE=YES
      shift # past argument
      ;;
    -*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

#### Functions
function print_usage() {
  echo ""
  echo "Options:"
  echo "    -a, --admin                        Print Keycloak admin password. This is a mutually exclusive option. See below for more details."
  echo "    -c, --console                      Print Keycloak console URL. This is a mutually exclusive option. See below for more details."
  echo "    -g, --generate                     Generate access token for application user (requires -u|--user). This is a mutually exclusive option. See below for more details."
  echo "    -u, --user string                  Application username (required when -g|--generate is set)."
  echo "    -i, --inspect                      Inspect access token (requires -t|--token). This is a mutually exclusive option. See below for more details."
  echo "    -t, --token string                 Access token (required when -i|--inspect is set)."
  echo "    -w, --wait-lb                      Wait for load balancer endpoint to become healthy (requires -l|--lb-arn-pattern). This is a mutually exclusive option. See below for more details."
  echo "    -l, --lb-arn-pattern string        Load balancer ARN pattern (required when -w|--wait-lb is set)."
  echo "    --authn                            Apply RequestAuthentication manifest. This is a mutually exclusive option. See below for more details."
  echo "    --authz                            Apply AuthorizationPolicy manifest. This is a mutually exclusive option. See below for more details."
  echo "    -n, --keycloak-namespace string    Namespace for keycloak (default keycloak)."
  echo "    -r, --keycloak-realm string        Keycloak realm for workshop (default workshop)."
  echo "    -h, --help                         Show this help message."
  echo "    -v, --verbose                      Enable verbose output."
  echo ""
  echo "**Mutually Exclusive Options:** Below options cannot appear together for an invocation of this command."
  echo "    -a, --admin"
  echo "    -c, --console"
  echo "    -g, --generate"
  echo "    -i, --inspect"
  echo "    --authn"
  echo "    --authz"
  echo "    -w, --wait-lb"
}

function handle_error() {
  echo ""
  echo "$1"
  exit 1
}

function handle_error_with_usage() {
  echo ""
  echo "$1"
  echo ""
  echo "Printing help..."
  print_usage
  exit 1
}

function handle_arg_help() {
  if [ "$SHOW_HELP" = "YES" ]; then
    print_usage
    exit 0
  fi
}

function validate_mutually_exclusive_args() {
  CNT=0
  if [ -n "$VERBOSE" ]; then
  echo "Validating if more than one mutually exclusive arguments are specified..."
  fi
  if [ -n "$PRINT_ADMIN_PASSWORD" ]; then
    ((CNT++))
  fi
  if [ -n "$PRINT_ADMIN_CONSOLE_URL" ]; then
    ((CNT++))
  fi
  if [ -n "$GENERATE_TOKEN" ]; then
    ((CNT++))
  fi
  if [ -n "$INSPECT_TOKEN" ]; then
    ((CNT++))
  fi
  if [ -n "$APPLY_AUTHN" ]; then
    ((CNT++))
  fi
  if [ -n "$APPLY_AUTHZ" ]; then
    ((CNT++))
  fi
  if [ -n "$WAIT_LB" ]; then
    ((CNT++))
  fi
  if [ $CNT -eq 0 ]; then
    handle_error_with_usage "ERROR: Any one of -a|--admin, -c|--console, -g|--generate, -i|--inspect, --authn, --authz, or -w|--wait-lb  is required."
  fi
  if [ $CNT -gt 1 ]; then
    handle_error_with_usage "ERROR: Arguments -a|--admin, -c|--console, -g|--generate, -i|--inspect, --authn, --authz, and -w|--wait-lb are mutually exclusive. Specify any one."
  fi
}

function validate_arg_generate() {
  if [ -n "$VERBOSE" ]; then
  echo "Validating arguments to generate access token..."
  fi
  if [ -n "$GENERATE_TOKEN" ]; then
    if [ -z "$APP_USER" ]; then
      handle_error_with_usage "ERROR: Application username is required for token generation. Use -u|--user option to specify application username."
    fi
  fi
}

function validate_arg_inspect() {
  if [ -n "$VERBOSE" ]; then
  echo "Validating arguments to inspect access token..."
  fi
  if [ -n "$INSPECT_TOKEN" ]; then
    if [ -z "$TOKEN" ]; then
      handle_error_with_usage "ERROR: Token is required for inspection. Use -t|--token option to specify token."
    fi
  fi
}

function validate_arg_wait_lb() {
  if [ -n "$VERBOSE" ]; then
  echo "Validating arguments to wait for load balncer healthy status..."
  fi
  if [ -n "$WAIT_LB" ]; then
    if [ -z "$LB_ARN_PATTERN" ]; then
      handle_error_with_usage "ERROR: Load balancer name pattern is required for -w|--wait-lb option. Use -l|--lb-arn-pattern option to specify load balancer name pattern."
    fi
  fi
}

function resolve_arg_keycloak_namespace() {
  if [ -n "$VERBOSE" ]; then
  echo "Resolving namespace for Keycloak..."
  fi
  if [ -z "$KEYCLOAK_NAMESPACE" ]; then
    KEYCLOAK_NAMESPACE=keycloak
  fi
}

function resolve_arg_keycloak_realm() {
  if [ -n "$VERBOSE" ]; then
  echo "Resolving Keycloak realm for Istio..."
  fi
  if [ -z "$KEYCLOAK_REALM" ]; then
    KEYCLOAK_REALM=workshop
  fi
}

function resolve_keycloak_config() {
  if [ -n "$VERBOSE" ]; then
  echo "Resolving Keycloak OIDC configurations..."
  fi
  
  KEYCLOAK_ENDPOINT=$(kubectl get service/keycloak -n "$KEYCLOAK_NAMESPACE" --output go-template --template='http://{{range .status.loadBalancer.ingress}}{{.hostname}}{{end}}')
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to retrieve keycloak endpoint."
  fi
  OPENID_CONFIG=$(curl -s "${KEYCLOAK_ENDPOINT}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration")
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to retrieve Open ID configuration."
  fi
  ISSUER=$(echo "${OPENID_CONFIG}" | jq -r '.issuer')
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to parse 'issuer' field from retrieved Open ID configuration."
  fi
  JWKS_URI=$(echo "${OPENID_CONFIG}" | jq -r '.jwks_uri')
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to parse 'jwks_uri' field from retrieved Open ID configuration."
  fi
  TOKEN_ENDPOINT=$(echo "${OPENID_CONFIG}" | jq -r '.token_endpoint')
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to parse 'token_endpoint' field from retrieved Open ID configuration."
  fi
}

function print_script_arguments() {
  if [ -n "$VERBOSE" ]; then
  echo ""
  echo "Script arguments:"
  echo "---------------------------------------------------------------------------------------------"
  echo "  KEYCLOAK_NAMESPACE........$KEYCLOAK_NAMESPACE"
  echo "  KEYCLOAK_REALM............$KEYCLOAK_REALM"
  if [ -n "$PRINT_ADMIN_PASSWORD" ]; then
  echo "  PRINT_ADMIN_PASSWORD......$PRINT_ADMIN_PASSWORD"
  fi
  if [ -n "$PRINT_ADMIN_CONSOLE_URL" ]; then
  echo "  PRINT_ADMIN_CONSOLE_URL...$PRINT_ADMIN_CONSOLE_URL"
  fi
  if [ -n "$GENERATE_TOKEN" ]; then
  echo "  GENERATE_TOKEN............$GENERATE_TOKEN"
  echo "  APP_USER..................$APP_USER"
  fi
  if [ -n "$INSPECT_TOKEN" ]; then
  echo "  INSPECT_TOKEN.............$INSPECT_TOKEN"
  echo "  TOKEN.....................$TOKEN"
  fi
  if [ -n "$APPLY_AUTHN" ]; then
  echo "  APPLY_AUTHN...............$APPLY_AUTHN"
  fi
  if [ -n "$APPLY_AUTHZ" ]; then
  echo "  APPLY_AUTHZ...............$APPLY_AUTHZ"
  fi
  if [ -n "$WAIT_LB" ]; then
  echo "  WAIT_LB...................$WAIT_LB"
  fi
  echo "  VERBOSE...................$VERBOSE"
  echo "---------------------------------------------------------------------------------------------"
  echo ""
  fi
}

function print_admin_password() {
  if [ -n "$VERBOSE" ]; then
  echo "Retrieving Keycloak admin user password from AWS Secrets Manager..."
  fi

  SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id keycloak --query "SecretString" --output text)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to retrieve Keycloak admin password from AWS SecretsManager."
  fi

  PASSWORD=$(echo "$SECRET_VALUE" | jq -r ".[\"admin_password\"]")
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to parse Keycloak admin password from AWS SecretsManager."
  fi
  if [ -n "$VERBOSE" ]; then
  echo "Username: admin"
  echo -n "Password: "
  fi
  echo "$PASSWORD"
}

function print_admin_console_url() {
  if [ -n "$VERBOSE" ]; then
  echo "Printing Keycloak admin console URL..."
  fi
  ADMIN_CONSOLE_URL=$(kubectl get service/keycloak -n $KEYCLOAK_NAMESPACE --output go-template --template='http://{{range .status.loadBalancer.ingress}}{{.hostname}}{{end}}/admin')
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to get Keycloak admin console URL."
  fi
  echo "$ADMIN_CONSOLE_URL"
}

function get_access_token() {
  if [ -n "$VERBOSE" ]; then
  echo "Retrieving access token from Keycloak..."
  fi

  resolve_keycloak_config

  if [ -n "$VERBOSE" ]; then
  echo "Retrieving password for application user ${APP_USER} from AWS Secrets Manager..."
  fi

  PASSWORD=$(aws secretsmanager get-secret-value --secret-id workshop-realm --query "SecretString" --output text | jq -r ".users[] | select(.username == \"${APP_USER}\") | .credentials[0].value")
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to retrieve user password for user ${APP_USER} from AWS SecretsManager."
  fi

  if [ -n "$VERBOSE" ]; then
  echo "Getting OIDC access token from Keycloak for user ${APP_USER}..."
  fi
  TOKEN_RESPONSE=$(curl \
    -s \
    --data-urlencode "client_id=productapp" \
    --data-urlencode "grant_type=password" \
    --data-urlencode "username=${APP_USER}" \
    --data-urlencode "password=${PASSWORD}" \
    "$TOKEN_ENDPOINT")
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to get access token response from Keycloak."
  fi
  TOKEN=$(echo "${TOKEN_RESPONSE}" | jq -r '.access_token')
  echo "$TOKEN"
}

# https://www.jvt.me/posts/2019/06/13/pretty-printing-jwt-openssl/
function jwt() {
  for part in 1 2; do
    b64="$(cut -f$part -d. <<< "$1" | tr '_-' '/+')"
    len=${#b64}
    n=$((len % 4))
    if [[ 2 -eq n ]]; then
      b64="${b64}=="
    elif [[ 3 -eq n ]]; then
      b64="${b64}="
    fi
    d="$(openssl enc -base64 -d -A <<< "$b64")"
    echo "$d"
    # don't decode further if this is an encrypted JWT (JWE)
    if [[ 1 -eq part ]] && grep '"enc":' <<< "$d" >/dev/null ; then
        exit 0
    fi
  done
}

function inspect_token() {
  if [ -n "$VERBOSE" ]; then
  echo "Inspecting JWT token..."
  fi
  INSPECTION_RESPONSE=$(jwt "$TOKEN")
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to inspect access token."
  fi
  if [ -n "$VERBOSE" ]; then
  echo "Decoded JWT"
  fi
  echo "${INSPECTION_RESPONSE}" | jq -r '.'
}

function apply_requestauthentication() {
  if [ -n "$VERBOSE" ]; then
  echo "Generating RequestAuthentication manifest from ${MODULE_DIR}/request-authentication/ingress-requestauthentication-template.yaml..."
  fi

  resolve_keycloak_config

  AUTH_DOC=$(sed "s#ISSUER#${ISSUER}#g" "${MODULE_DIR}/request-authentication/ingress-requestauthentication-template.yaml" \
    | sed "s#JWKS_URI#${JWKS_URI}#g")
  if [ -n "$VERBOSE" ]; then
  echo "Generated manifest:"
  echo "-------------------"
  echo "${AUTH_DOC}"
  echo "-------------------"
  fi
  echo "${AUTH_DOC}" | kubectl apply -f -
}

function apply_authorizationpolicy() {
  if [ -n "$VERBOSE" ]; then
  echo "Applying AuthorizationPolicy manifest $MODULE_DIR/request-authentication/ingress-authorizationpolicy.yaml..."
  echo "Manifest:"
  echo "-------------------"
  cat "${MODULE_DIR}/request-authentication/ingress-authorizationpolicy.yaml"
  echo "-------------------"
  fi
  kubectl apply -f "${MODULE_DIR}/request-authentication/ingress-authorizationpolicy.yaml"
}

function wait_for_load_balancer() {
  if [ -n "$VERBOSE" ]; then
  echo "Waiting for load balancer to become healthy..."
  fi

  if [ -n "$VERBOSE" ]; then
  echo "Trying to locate load balancer using ARN pattern '$LB_ARN_PATTERN'..."
  fi
  LB_ARN=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerArn, \`$LB_ARN_PATTERN\`)].LoadBalancerArn" --output text)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to describe load balancer."
  fi

  if [ -z "$LB_ARN" ]; then
    handle_error "ERROR: Could not locate load balancer resource. Is the region set correctly?"
  fi

  if [ -n "$VERBOSE" ]; then
  echo "Trying to locate target group for load balancer ARN '$LB_ARN'..."
  fi
  TARGET_GRP_ARN=$(aws elbv2 describe-target-groups --load-balancer-arn "$LB_ARN" --query 'TargetGroups[0].TargetGroupArn' --output text)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to describe target group."
  fi

  if [ -z "$TARGET_GRP_ARN" ]; then
    handle_error "ERROR: Could not locate load balancer target group."
  fi

  if [ -n "$VERBOSE" ]; then
  echo "Query target group health..."
  fi
  TARGET_HEALTH=$(aws elbv2 describe-target-health --target-group-arn "$TARGET_GRP_ARN" --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to describe keycloak target health."
  fi

  while [ "$TARGET_HEALTH" != "healthy" ]
  do
    if [ -n "$VERBOSE" ]; then
    echo "Target health is $TARGET_HEALTH. Waiting 10 seconds."
    fi
    sleep 10
    TARGET_HEALTH=$(aws elbv2 describe-target-health --target-group-arn "$TARGET_GRP_ARN" --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text)
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to describe keycloak target health."
    fi
  done

  if [ -n "$VERBOSE" ]; then
  echo "Target health is $TARGET_HEALTH."
  fi
}

# https://stackoverflow.com/questions/59895/how-do-i-get-the-directory-where-a-bash-script-is-located-from-within-the-script
function resolve_script_dir() {
  if [ -n "$VERBOSE" ]; then
  echo "Resolving script directory..."
  fi
  SOURCE=${BASH_SOURCE[0]}
  while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
    SCRIPT_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
    SOURCE=$(readlink "$SOURCE")
    [[ $SOURCE != /* ]] && SOURCE=$SCRIPT_DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  done
  SCRIPT_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  if [ -n "$VERBOSE" ]; then
  echo "Resolved script directory: ${SCRIPT_DIR}"
  fi
}

function resolve_module_dir() {
  if [ -n "$VERBOSE" ]; then
  echo "Resolving module directory..."
  fi
  MODULE_DIR="$SCRIPT_DIR/.."
  if [ -n "$VERBOSE" ]; then
  echo "Resolved module directory: ${MODULE_DIR}"
  fi
}

function dispatch_call() {
  if [ -n "$VERBOSE" ]; then
  echo "Dispatching call to handler function..."
  fi
  
  if [ -n "$PRINT_ADMIN_PASSWORD" ]; then
    print_admin_password
  fi
  if [ -n "$PRINT_ADMIN_CONSOLE_URL" ]; then
    print_admin_console_url
  fi
  if [ -n "$GENERATE_TOKEN" ]; then
    get_access_token
  fi
  if [ -n "$INSPECT_TOKEN" ]; then
    inspect_token
  fi
  if [ -n "$APPLY_AUTHN" ]; then
    apply_requestauthentication
  fi
  if [ -n "$APPLY_AUTHZ" ]; then
    apply_authorizationpolicy
  fi
  if [ -n "$WAIT_LB" ]; then
    wait_for_load_balancer
  fi
}

#### Main ####
handle_arg_help

validate_mutually_exclusive_args

validate_arg_generate

validate_arg_inspect

validate_arg_wait_lb

resolve_arg_keycloak_namespace

resolve_arg_keycloak_realm

resolve_script_dir

resolve_module_dir

print_script_arguments

dispatch_call