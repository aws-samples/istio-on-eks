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

#title           04-keycloak-helpers.sh
#description     This script contains helper functions to interact with Keycloak related resources for Istio request authentication.
#author          Sourav Paul (@psour)
#contributors    @psour
#date            2024-01-19
#version         1.0
#usage           ./04-keycloak-helpers.sh [-a|--admin] [-c|--console] [-g|--generate -u|--user <USER>] [--authn] [--authz] [-n|--keycloak-namespace <KEYCLOAK_NAMESPACE>] [-r|--keycloak-realm <KEYCLOAK_REALM>] [-h|--help] [-v|--verbose]
#==============================================================================

#echo ---------------------------------------------------------------------------------------------
#echo "This script contains helper functions to interact with Keycloak related resources for Istio request authentication."
#echo ---------------------------------------------------------------------------------------------

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
    -i|--introspect)
      INTROSPECT_TOKEN=YES
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
    -h|--help)
      SHOW_HELP=YES
      shift # past argument
      ;;
    -v|--verbose)
      VERBOSE=YES
      shift # past argument
      ;;
    -*|--*)
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
  echo "    -a, --admin                        Print Keycloak admin password. Mutually exclusive with -c|--console, -g|--generate, -i|--introspect, --authn and --authz."
  echo "    -c, --console                      Print Keycloak console URL. Mutually exclusive with -a|--admin, -g|--generate, -i|--introspect, --authn and --authz."
  echo "    -g, --generate                     Generate access token for application user (requires -u|--user). Mutually exclusive with -a|--admin, -c|--console, -i|--introspect, --authn and --authz."
  echo "    -u, --user string                  Application username (required when -g|--generate is set)."
  echo "    -i, --introspect                   Introspect access token (requires -t|--token). Mutually exclusive with -a|--admin, -c|--console, -g|--generate, --authn and --authz."
  echo "    -t, --token string                 Access token (required when -i|--introspect is set)."
  echo "    --authn                            Apply RequestAuthentication manifest. Mutually exclusive with -a|--admin, -c|--console, -g|--generate, -i|--introspect and --authz."
  echo "    --authz                            Apply AuthorizationPolicy manifest. Mutually exclusive with -a|--admin, -c|--console, -g|--generate, -i|--introspect and --authn."
  echo "    -n, --keycloak-namespace string    Namespace for keycloak (default keycloak)."
  echo "    -r, --keycloak-realm string        Keycloak realm for istio (default istio)."
  echo "    -h, --help                         Show this help message."
  echo "    -v, --verbose                      Enable verbose logging."
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
  if [ -n "$INTROSPECT_TOKEN" ]; then
    ((CNT++))
  fi
  if [ -n "$APPLY_AUTHN" ]; then
    ((CNT++))
  fi
  if [ -n "$APPLY_AUTHZ" ]; then
    ((CNT++))
  fi
  if [ $CNT -eq 0 ]; then
    handle_error_with_usage "ERROR: Any one of -a|--admin, -c|--console, -g|--generate, -i|--introspect, --authn or --authz is required."
  fi
  if [ $CNT -gt 1 ]; then
    handle_error_with_usage "ERROR: Arguments -a|--admin, -c|--console, -g|--generate, -i|--introspect, --authn and --authz are mutually exclusive. Specify any one."
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

function validate_arg_introspect() {
  if [ -n "$VERBOSE" ]; then
  echo "Validating arguments to introspect access token..."
  fi
  if [ -n "$INTROSPECT_TOKEN" ]; then
    if [ -z "$TOKEN" ]; then
      handle_error_with_usage "ERROR: Token is required for introspection. Use -t|--token option to specify token."
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
    KEYCLOAK_REALM=istio
  fi
}

function resolve_keycloak_config() {
  if [ -n "$VERBOSE" ]; then
  echo "Resolving Keycloak OIDC configurations..."
  fi
  
  KEYCLOAK_ENDPOINT=$(kubectl get service/keycloak -n "$KEYCLOAK_NAMESPACE" --output go-template --template='http://{{range .status.loadBalancer.ingress}}{{.hostname}}{{end}}')
  OPENID_CONFIG=$(curl -s "${KEYCLOAK_ENDPOINT}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration")
  ISSUER=$(echo "${OPENID_CONFIG}" | jq -r '.issuer')
  JWKS_URI=$(echo "${OPENID_CONFIG}" | jq -r '.jwks_uri')
  TOKEN_ENDPOINT=$(echo "${OPENID_CONFIG}" | jq -r '.token_endpoint')
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
  if [ -n "$INTROSPECT_TOKEN" ]; then
  echo "  INTROSPECT_TOKEN..........$INTROSPECT_TOKEN"
  echo "  TOKEN.....................$TOKEN"
  fi
  if [ -n "$APPLY_AUTHN" ]; then
  echo "  APPLY_AUTHN...............$APPLY_AUTHN"
  fi
  if [ -n "$APPLY_AUTHZ" ]; then
  echo "  APPLY_AUTHZ...............$APPLY_AUTHZ"
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
  PASSWORD=$(aws secretsmanager get-secret-value --secret-id istio/keycloak --query "SecretString" --output text | jq -r ".[\"admin-password\"]")
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to retrieve Keycloak admin password from AWS SecretsManager."
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
  echo "Retrieving password for application user ${APP_USER} from AWS Secrets Manager..."
  fi
  PASSWORD=$(aws secretsmanager get-secret-value --secret-id istio/keycloak --query "SecretString" --output text | jq -r ".[\"user-${APP_USER}-password\"]")
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

function introspect_token() {
  if [ -n "$VERBOSE" ]; then
  echo "Introspecting JWT token..."
  fi
  INTROSPECTION_RESPONSE=$(jwt "$TOKEN")
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to introspect access token."
  fi
  echo "Decoded JWT"
  echo "${INTROSPECTION_RESPONSE}" | jq -r '.'
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
  MODULE_DIR="$SCRIPT_DIR/../modules/04-security"
  if [ -n "$VERBOSE" ]; then
  echo "Resolved module directory: ${MODULE_DIR}"
  fi
}

function apply_requestauthentication() {
  if [ -n "$VERBOSE" ]; then
  echo "Generating RequestAuthentication manifest from ${MODULE_DIR}/request-authentication/ingress-requestauthentication-template.yaml..."
  fi
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
  if [ -n "$INTROSPECT_TOKEN" ]; then
    introspect_token
  fi
  if [ -n "$APPLY_AUTHN" ]; then
    apply_requestauthentication
  fi
  if [ -n "$APPLY_AUTHZ" ]; then
    apply_authorizationpolicy
  fi
}

#### Main ####

handle_arg_help

validate_mutually_exclusive_args

validate_arg_generate

validate_arg_introspect

resolve_arg_keycloak_namespace

resolve_arg_keycloak_realm

resolve_keycloak_config

resolve_script_dir

resolve_module_dir

print_script_arguments

dispatch_call