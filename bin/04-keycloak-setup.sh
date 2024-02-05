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

#title           04-keycloak-setup.sh
#description     This script sets up keycloak related resources for Istio request authentication.
#author          Sourav Paul (@psour)
#contributors    @psour
#date            2024-01-19
#version         1.0
#usage           ./04-keycloak-setup.sh -c|--cluster-name <CLUSTER_NAME> [-a|--account-id <ACCOUNT_ID>] [-n|--keycloak-namespace <KEYCLOAK_NAMESPACE>] [-r|--keycloak-realm <KEYCLOAK_REALM>] [-h|--help]
#==============================================================================

echo ---------------------------------------------------------------------------------------------
echo "This script sets up keycloak related resources for Istio request authentication."
echo ---------------------------------------------------------------------------------------------

#### Resolve command line arguments
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--account-id)
      ACCOUNT_ID="$2"
      shift # past argument
      shift # past value
      ;;
    -c|--cluster-name)
      CLUSTER_NAME="$2"
      shift # past argument
      shift # past value
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
  echo "    -a, --account_id string            AWS account id (default inferred from ACCOUNT_ID environment variable or else by calling STS GetCallerIdentity)"
  echo "    -c, --cluster-name string          Amazon EKS cluster name"
  echo "    -n, --keycloak-namespace string    Namespace for keycloak (default keycloak)"
  echo "    -r, --keycloak-realm string        Keycloak realm for istio (default istio)"
  echo "    -h, --help                         Show this help message"
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

function resolve_arg_account_id() {
  if [ -z "$ACCOUNT_ID" ]; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error_with_usage "ERROR: Failed to invoke STS GetCallerIdentity."
    fi
    if [ -z "$ACCOUNT_ID" ]; then
      handle_error_with_usage "ERROR: Could not infer ACCOUNT_ID."
    fi
  fi
}

function validate_arg_cluster_name() {
  if [ -z "$CLUSTER_NAME" ]; then
    handle_error_with_usage "ERROR: Amazon EKS cluster name is required."
  fi
}

function resolve_arg_keycloak_namespace() {
  if [ -z "$KEYCLOAK_NAMESPACE" ]; then
    KEYCLOAK_NAMESPACE=keycloak
  fi
}

function resolve_arg_keycloak_realm() {
  if [ -z "$KEYCLOAK_REALM" ]; then
    KEYCLOAK_REALM=istio
  fi
}

function print_script_arguments() {
  echo ""
  echo "Script arguments:"
  echo "---------------------------------------------------------------------------------------------"
  echo "  ACCOUNT_ID..........$ACCOUNT_ID"
  echo "  CLUSTER_NAME........$CLUSTER_NAME"
  echo "  KEYCLOAK_NAMESPACE..$KEYCLOAK_NAMESPACE"
  echo "  KEYCLOAK_REALM......$KEYCLOAK_REALM"
  echo "---------------------------------------------------------------------------------------------"
  echo ""
}

function locate_eks_cluster() {
  echo "Searching Amazon EKS cluster with name '$CLUSTER_NAME'..."
  CLUSTER_META=$(aws eks describe-cluster --name $CLUSTER_NAME)
  CMD_RESULT=$?
  if [ -z "$CLUSTER_META" ] || [ $CMD_RESULT -ne 0 ] ; then
    handle_error "ERROR: Could not locate Amazon EKS cluster with name '$CLUSTER_NAME'."
  fi
  echo "Found Amazon EKS cluster."
  CLUSTER_OIDC_ISSUER_URL=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text)
  CLUSTER_OIDC_ISSUER=${CLUSTER_OIDC_ISSUER_URL#*https://}
}

function attach_policy_to_role() {
  ROLE_NAME="$1"
  POLICY_ARN="$2"
  echo "Attaching IAM policy ${POLICY_ARN} to IAM role ${ROLE_NAME}..."
  aws iam attach-role-policy \
    --policy-arn "$POLICY_ARN" \
    --role-name "$ROLE_NAME"
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to attach IAM policy ${POLICY_ARN} to IAM role ${ROLE_NAME}."
  fi
}

function create_iam_role_for_sa() {
  ROLE_NAME="$1"
  NAMESPACE="$2"
  SERVICE_ACCOUNT_NAME="$3"
  POLICY_ARN="$4"
  echo "Checking if IAM role ${ROLE_NAME} already exists..."
  ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text 2>&1)
  CMD_RESULT=$?
  if [[ $ROLE_ARN == *"(NoSuchEntity)"* ]]; then
    echo "IAM role ${ROLE_NAME} will be created."
    ROLE_DOC=$(cat <<EoM
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${CLUSTER_OIDC_ISSUER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${CLUSTER_OIDC_ISSUER}:aud": "sts.amazonaws.com",
          "${CLUSTER_OIDC_ISSUER}:sub": "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT_NAME}"
        }
      }
    }
  ]
}
EoM
)
    ROLE_ARN=$(aws iam create-role \
      --role-name "$ROLE_NAME" \
      --assume-role-policy-document "$ROLE_DOC" \
      --query "Role.Arn" \
      --tags "Key=Project,Value=Istio-on-EKS" \
      --output text)
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to create IAM role ${ROLE_NAME}."
    fi

    attach_policy_to_role \
      "$ROLE_NAME" \
      "$POLICY_ARN"
  elif [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to query IAM role ${ROLE_NAME}."
  else
    echo "Checking if IAM policy ${POLICY_ARN} is attached to IAM role ${ROLE_NAME}..."
    ATTACHED_POLICY_FOUND=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query "length(AttachedPolicies[?PolicyArn==\`${POLICY_ARN}\`])" --output text)
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to check whether IAM policy ${POLICY_ARN} is attached to IAM role ${ROLE_NAME}."
    fi
    if [ $ATTACHED_POLICY_FOUND -eq 0 ]; then
      attach_policy_to_role \
        "$ROLE_NAME" \
        "$POLICY_ARN"
    fi
  fi
}

function install_ebs_csi_driver() {
  echo "Installing EBS CSI driver addon..."

  create_iam_role_for_sa \
    "istio-eks-ebs-csi-driver-role" \
    "kube-system" \
    "ebs-csi-controller-sa" \
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"

  echo "Searching if EBS CSI driver addon is installed in the cluster..."
  EBS_CSI_ADDON=$(aws eks list-addons --cluster-name "$CLUSTER_NAME" --query 'addons[?@==`aws-ebs-csi-driver`]' --output text)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to list EKS addons."
  fi

  if [ -z "$EBS_CSI_ADDON" ]; then
    echo "The EBS CSI driver addon will be installed in the cluster."
    EBS_CSI_CREATE_RESPONSE=$(aws eks create-addon \
      --cluster-name "$CLUSTER_NAME" \
      --addon-name aws-ebs-csi-driver \
      --service-account-role-arn "$ROLE_ARN" \
      --tags "Key=Project,Value=Istio-on-EKS" \
      2>&1)
    
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to install EBS CSI driver addon. Detailed error response: ${EBS_CSI_CREATE_RESPONSE}"
    fi

    EBS_CSI_CREATE_STATUS=$(echo "${EBS_CSI_CREATE_RESPONSE}" | jq -r '.addon.status')
    echo "EBS CSI driver addon status: ${EBS_CSI_CREATE_STATUS}"
    
    echo "Waiting for EBS CSI driver addon status to become 'ACTIVE'..."
    aws eks wait addon-active \
      --cluster-name "$CLUSTER_NAME" \
      --addon-name aws-ebs-csi-driver
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to wait on EBS CSI driver addon status to become 'ACTIVE'."
    fi
  else
    echo "Found EBS CSI driver addon is already installed in the cluster."
  fi

  EBS_SC=ebs-sc
  echo "Checking if StorageClass '$EBS_SC' exists..."
  CMD_OUT=$(kubectl get storageclass $EBS_SC -o jsonpath='{.metadata.name}' 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *"NotFound"* )
        echo "StorageClass '$EBS_SC' will be created."
        CMD_OUT=$(cat <<EOF | kubectl apply -f - 2>&1
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $EBS_SC
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
EOF
)
        CMD_RESULT=$?
        if [ $CMD_RESULT -ne 0 ]; then
          case "$CMD_OUT" in
            *"AlreadyExists"* )
              echo "WARNING: StorageClass '$EBS_SC' already exists. May be created by another concurrent process."
              ;;
            *)
              handle_error "ERROR: Failed to create EBS StorageClass '$EBS_SC'."
              ;;
          esac
        fi
        ;;
      *)
        handle_error "ERROR: Failed to check if StorageClass '$EBS_SC' exists."
        ;;
    esac
  else
    echo "StorageClass '$EBS_SC' already exists."
  fi
}

function check_helm() {
  echo "Checking if helm is installed."
  HELM_VER=$(helm version --short 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    echo "Helm will be installed."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Could not download helm installation script."
    fi
    chmod 700 get_helm.sh
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Could not change file permissions of the downloaded helm installation script 'get_helm.sh'."
    fi
    ./get_helm.sh
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Helm installation failed with code $CMD_RESULT."
    fi
    echo "Removing helm installation script 'get_helm.sh'..."
    rm -rf get_helm.sh
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      echo "WARNING: Could not remove helm installation script 'get_helm.sh'. Please remove it manually."
    fi
  else
    echo "Helm $HELM_VER is installed."
  fi
}

function add_helm_repo() {
  REPO=$1
  REPO_URL=$2
  echo "Searching if helm repo '$REPO' is installed..."
  HELM_REPO=$(helm repo list -o json | jq -r ".[] | select(.name == \"$REPO\") | .name")
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to list helm repo '$REPO'."
  fi
  if [ -z "$HELM_REPO" ]; then
    echo "Adding helm repo '$REPO'..."
    helm repo add "$REPO" "$REPO_URL"
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to add helm repo '$REPO'."
    fi
  else
    echo "Found helm repo '$REPO'."
  fi
}

function install_external_secrets() {
  echo "Searching if application 'external-secrets' is installed..."
  EXT_SECRET_REL=$(helm list -f external-secrets -n external-secrets -o json -q)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to list application 'external-secrets'."
  fi
  
  if [ "$EXT_SECRET_REL" != "[]" ]; then
    echo "Application 'external-secrets' is already installed."
    return 0
  fi
  
  echo "Application 'external-secrets' will be installed."
  echo "---------------------------------------------------------------------------------------------"
  helm install external-secrets \
     external-secrets/external-secrets \
      -n external-secrets \
      --create-namespace
  CMD_RESULT=$?
  echo "---------------------------------------------------------------------------------------------"
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to execute helm install external-secrets."
  fi

  echo "Checking if Endpoints object for 'external-secrets-webhook' is ready..."
  PROBE_CNT=0
  while [ $PROBE_CNT -lt 30 ]
  do
    CMD_OUT=$(kubectl get endpoints/external-secrets-webhook -n external-secrets -o jsonpath='{.subsets}' 2>&1)
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      case "$CMD_OUT" in
        *"NotFound"* )
          # Endpoints object not yet created. Wait a little longer...
          ;;
        *)
          handle_error "ERROR: Failed to check if Endpoints object exists for 'external-secrets-webhook'."
          ;;
      esac
    elif [ -n "$CMD_OUT" ]; then
      SUBSETS_CNT=$(echo "$CMD_OUT" | jq -rc '. | length')
      CMD_RESULT=$?
      if [ $CMD_RESULT -ne 0 ]; then
        handle_error "ERROR: Failed to check length of Endpoints subsets for 'external-secrets-webhook'."
      fi
      echo "Endpoints subsets count: ${SUBSETS_CNT}"
      if [ "$SUBSETS_CNT" -gt 0 ]; then
        echo "Endpoints object for 'external-secrets-webhook' is ready."
        break
      fi
    fi
    echo "No endpoint addresses found for 'external-secrets-webhook'. Waiting 10 seconds."
    ((PROBE_CNT++))
    sleep 10
  done
}

function configure_keycloak_password() {
  echo "Checking saved keycloak password in AWS Secrets Manager..."
  SECRET_NAME="istio/keycloak"
  SECRET_ARN=$(aws secretsmanager list-secrets --filters Key=name,Values=$SECRET_NAME Key=tag-key,Values=Project Key=tag-value,Values=Istio-on-EKS --query "SecretList[0].ARN" --output text)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to check saved keycloak password in AWS Secrets Manager."
  fi
  if [ "$SECRET_ARN" != "None" ]; then
    echo "Found saved keycloak password. Retrieving saved value..."
    KEYCLOAK_PASSWORDS=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query "SecretString" --output text)
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to retrieve saved keycloak password from AWS Secrets Manager."
    fi
    KEYCLOAK_ADMIN_PASSWORD=$(echo "$KEYCLOAK_PASSWORDS" | jq -r '.["admin-password"]')
    KEYCLOAK_USER_ALICE_PASSWORD=$(echo "$KEYCLOAK_PASSWORDS" | jq -r '.["user-alice-password"]')
    KEYCLOAK_USER_BOB_PASSWORD=$(echo "$KEYCLOAK_PASSWORDS" | jq -r '.["user-bob-password"]')
    KEYCLOAK_USER_CHARLIE_PASSWORD=$(echo "$KEYCLOAK_PASSWORDS" | jq -r '.["user-charlie-password"]')
  else
    echo "Generating keycloak password..."
    KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -base64 8)
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to generate keycloak admin password."
    fi
    KEYCLOAK_USER_ALICE_PASSWORD=$(openssl rand -base64 8)
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to generate keycloak user Alice password."
    fi
    KEYCLOAK_USER_BOB_PASSWORD=$(openssl rand -base64 8)
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to generate keycloak user Bob password."
    fi
    KEYCLOAK_USER_CHARLIE_PASSWORD=$(openssl rand -base64 8)
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to generate keycloak user Charlie password."
    fi
    echo "Saving generated keycloak passwords in AWS Secrets Manager..."
    SECRET_ARN=$(aws secretsmanager create-secret \
      --name $SECRET_NAME \
      --secret-string "{\"admin-password\":\"$KEYCLOAK_ADMIN_PASSWORD\",\"user-alice-password\":\"$KEYCLOAK_USER_ALICE_PASSWORD\",\"user-bob-password\":\"$KEYCLOAK_USER_BOB_PASSWORD\",\"user-charlie-password\":\"$KEYCLOAK_USER_CHARLIE_PASSWORD\"}" \
      --tags "Key=Project,Value=Istio-on-EKS" \
      --query "ARN" \
      --output text)
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to save generated keycloak passwords in AWS Secrets Manager."
    fi
  fi
}

function ensure_namespace_exists() {
  NAMESPACE="$1"
  echo "Checking if namespace '${NAMESPACE}' exists..."
  CMD_OUT=$(kubectl get ns "${NAMESPACE}" -o jsonpath='{.metadata.name}' 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *"NotFound"* )
        echo "Namespace '${NAMESPACE}' will be created."
        CMD_OUT=$(kubectl create ns "${NAMESPACE}" 2>&1)
        CMD_RESULT=$?
        if [ $CMD_RESULT -ne 0 ]; then
          case "$CMD_OUT" in
            *"AlreadyExists"* )
              echo "WARNING: Namespace '${NAMESPACE}' already exists. May be created by another concurrent process."
              ;;
            *)
              handle_error "ERROR: Failed to create namespace '${NAMESPACE}'."
              ;;
          esac
        fi
        ;;
      *)
        handle_error "ERROR: Failed to check if namespace '${NAMESPACE}' exists."
        ;;
    esac
  else
    echo "Namespace '${NAMESPACE}' exists."
  fi
}

function ensure_service_account_exists() {
  NAMESPACE="$1"
  SERVICE_ACCOUNT="$2"
  echo "Checking if service account '${SERVICE_ACCOUNT}' exists in namespace ${NAMESPACE}..."
  CMD_OUT=$(kubectl get sa "${SERVICE_ACCOUNT}" -n "${NAMESPACE}" -o jsonpath='{.metadata.name}' 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *"NotFound"* )
        echo "Service account '${SERVICE_ACCOUNT}' will be created in namespace ${NAMESPACE}."
        CMD_OUT=$(kubectl create sa "${SERVICE_ACCOUNT}" -n "${NAMESPACE}" 2>&1)
        CMD_RESULT=$?
        if [ $CMD_RESULT -ne 0 ]; then
          case "$CMD_OUT" in
            *"AlreadyExists"* )
              echo "WARNING: Service account '${SERVICE_ACCOUNT}' already exists in namespace ${NAMESPACE}. May be created by another concurrent process."
              ;;
            *)
              handle_error "ERROR: Failed to create service account '${SERVICE_ACCOUNT}' in namespace '${NAMESPACE}'."
              ;;
          esac
        fi
        ;;
      *)
        handle_error "ERROR: Failed to check if service account '${SERVICE_ACCOUNT}' exists in namespace '${NAMESPACE}'."
        ;;
    esac
  else
    echo "Service account '${SERVICE_ACCOUNT}' exists in namespace '${NAMESPACE}'."
  fi
}

function configure_keycloak_externalsecret() {
  echo "Checking existing IAM policy information for keycloak SecretStore..."
  POLICY_NAME=istio-keycloak-secretstore-policy
  POLICY_ARN=$(aws iam get-policy --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/${POLICY_NAME}" --query "Policy.Arn" --output text 2>&1)
  CMD_RESULT=$?
  if [[ $CMD_RESULT -ne 0 ]] && [[ "$POLICY_ARN" =~ ^.*(NoSuchEntity).*$ ]]; then
    echo "Creating new IAM policy for keycloak SecretStore..."
    POLICY_DOC=$(cat <<EOF | jq --compact-output -r '.'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:$AWS_REGION:$ACCOUNT_ID:secret:istio/keycloak-*"
    }
  ]
}
EOF
)
    POLICY_ARN=$(aws iam create-policy \
      --policy-name "$POLICY_NAME" \
      --policy-document "$POLICY_DOC" \
      --tags "Key=Project,Value=Istio-on-EKS" \
      --query "Policy.Arn" \
      --output text)
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to create new IAM policy for keycloak SecretStore."
    fi
  elif [[ $CMD_RESULT -ne 0 ]]; then
    handle_error "ERROR: Failed to check existing IAM policy information for keycloak SecretStore."
  fi

  SERVICE_ACCOUNT=keycloaksecretstore
  create_iam_role_for_sa \
    "istio-keycloak-secretstore-role" \
    "${KEYCLOAK_NAMESPACE}" \
    "${SERVICE_ACCOUNT}" \
    "${POLICY_ARN}"

  ensure_namespace_exists "${KEYCLOAK_NAMESPACE}"

  ensure_service_account_exists \
    "${KEYCLOAK_NAMESPACE}" \
    "${SERVICE_ACCOUNT}"

  kubectl annotate --overwrite sa -n "$KEYCLOAK_NAMESPACE" "$SERVICE_ACCOUNT" eks.amazonaws.com/role-arn="${ROLE_ARN}"
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to annotate service account '${SERVICE_ACCOUNT}' with IAM role '${ROLE_ARN}'."
  fi
  
  echo "Checking existing keycloak SecretStore..."
  CMD_OUT=$(kubectl get secretstore keycloak -n "$KEYCLOAK_NAMESPACE" -o jsonpath='{.metadata.name}' 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *NotFound* )
        echo "Keycloak SecretStore will be created."
        SECRET_STORE_DOC=$(cat<<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: keycloak
  namespace: $KEYCLOAK_NAMESPACE
spec:
  provider:
    aws:
      service: SecretsManager
      region: $AWS_REGION
      auth:
        jwt:
          serviceAccountRef:
            name: $SERVICE_ACCOUNT
EOF
)
        CMD_OUT=$(echo "$SECRET_STORE_DOC" | kubectl apply -f - 2>&1)
        CMD_RESULT=$?
        if [ $CMD_RESULT -ne 0 ]; then
          if [[ "$CMD_OUT" == *"no endpoints available for service"* ]]; then
            echo "Webhook endpoints unavailable. Waiting for 30 seconds..."
            sleep 30
            CMD_OUT=$(echo "$SECRET_STORE_DOC" | kubectl apply -f - 2>&1)
            CMD_RESULT=$?
            if [ $CMD_RESULT -ne 0 ]; then
              handle_error "ERROR: Failed to create keycloak SecretStore. Detailed error response: ${CMD_OUT}"
            fi
          else
            handle_error "ERROR: Failed to create keycloak SecretStore. Detailed error response: ${CMD_OUT}"
          fi
          # Error from server (InternalError): error when creating "STDIN": Internal error occurred: failed calling webhook "validate.secretstore.external-secrets.io": failed to call webhook: Post "https://external-secrets-webhook.external-secrets.svc:443/validate-external-secrets-io-v1beta1-secretstore?timeout=5s": no endpoints available for service "external-secrets-webhook"
        fi
        ;;
      *)
        handle_error "ERROR: Failed to check existing keycloak SecretStore."
        ;;
    esac
  else
    echo "Found existing keycloak SecretStore."
  fi
  
  echo "Checking existing keycloak ExternalSecret..."
  CMD_OUT=$(kubectl get externalsecret keycloak -n keycloak -o jsonpath='{.metadata.name}' 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *NotFound* )
        echo "Creating keycloak ExternalSecret..."
        cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: keycloak
  namespace: $KEYCLOAK_NAMESPACE
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: keycloak
    kind: SecretStore
  target:
    name: keycloak
    creationPolicy: Owner
  data:
  - secretKey: admin-password
    remoteRef:
      key: istio/keycloak
      property: admin-password
EOF
  
        CMD_RESULT=$?
        if [ $CMD_RESULT -ne 0 ]; then
          handle_error "ERROR: Failed to create keycloak ExternalSecret."
        fi
        ;;
      *)
        handle_error "ERROR: Failed to check existing keycloak ExternalSecret."
        ;;
    esac
  else
    echo "Found existing keycloak ExternalSecret."
  fi
}

function install_keycloak() {
  echo "Searching if application 'keycloak' is already installed..."
  KEYCLOAK_REL=$(helm list -f keycloak -n keycloak -o json -q)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to list application 'keycloak'."
  fi
  
  if [ "$KEYCLOAK_REL" != "[]" ]; then
    echo "Application 'keycloak' is already installed."
    return 0
  fi
  
  echo "Application 'keycloak' will be installed."
  
  echo "Generating keycloak chart values..."
  KEYCLOAK_HELM_VALUES=$(cat <<EOF
global:
  storageClass: "ebs-sc"
image:
  registry: public.ecr.aws
  repository: bitnami/keycloak
  tag: 22.0.1-debian-11-r36
  debug: true
auth:
  adminUser: admin
  existingSecret: keycloak
  passwordSecretKey: admin-password
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
  http:
    enabled: true
  ports:
    http: 80
EOF
)

  echo "Executing helm install keycloak..."
  echo "---------------------------------------------------------------------------------------------"
  echo "$KEYCLOAK_HELM_VALUES" | helm install keycloak bitnami/keycloak \
    --namespace "$KEYCLOAK_NAMESPACE" \
    -f -
  CMD_RESULT=$?
  echo "---------------------------------------------------------------------------------------------"
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to execute helm install keycloak."
  fi
}

function configure_keycloak() {
  echo "Configuring keycloak..."
  REALM_JSON=$(cat <<EOF
{
  "realm": "${KEYCLOAK_REALM}",
  "enabled": true,
  "sslRequired": "none",
  "roles": {
    "realm": [
      {
        "name": "admin"
      },
      {
        "name": "guest"
      },
      {
        "name": "other"
      }
    ]
  },
  "users": [
    {
      "id": "alice@example.com",
      "username": "alice",
      "email": "alice@example.com",
      "emailVerified": true,
      "enabled": true,
      "firstName": "Alice",
      "createdTimestamp": $(date +%s),
      "realmRoles": [
         "guest"
      ]
    },
    {
      "id": "bob@example.com",
      "username": "bob",
      "email": "bob@example.com",
      "emailVerified": true,
      "enabled": true,
      "firstName": "Bob",
      "createdTimestamp": $(date +%s),
      "realmRoles": [
        "admin"
      ]
    },
    {
      "id": "charlie@example.com",
      "username": "charlie",
      "email": "charlie@example.com",
      "emailVerified": true,
      "enabled": true,
      "firstName": "Charlie",
      "createdTimestamp": $(date +%s),
      "realmRoles": [
        "other"
      ]
    }
  ],
  "requiredCredentials": [
    "password"
  ],
  "clients": [
    {
      "clientId": "productapp",
      "name": "productapp",
      "enabled": true,
      "clientAuthenticatorType": "client-secret",
      "publicClient": true,
      "directAccessGrantsEnabled": true,
      "protocol": "openid-connect",
      "redirectUris": [
        "/*"
      ],
      "webOrigins": [
        "/*"
      ],
      "attributes": {
        "oidc.ciba.grant.enabled": "false",
        "oauth2.device.authorization.grant.enabled": "false",
        "backchannel.logout.session.required": "true",
        "backchannel.logout.revoke.offline.tokens": "false"
      },
      "protocolMappers": [
        {
          "name": "AudienceMapper",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-audience-mapper",
          "consentRequired": false,
          "config": {
            "included.client.audience": "productapp",
            "id.token.claim": "false",
            "access.token.claim": "true",
            "introspection.token.claim": "true"
          }
        }
      ],
      "defaultClientScopes": [
        "web-origins",
        "acr",
        "profile",
        "roles",
        "email"
      ],
      "optionalClientScopes": [
        "address",
        "phone",
        "offline_access",
        "microprofile-jwt"
      ]
    }
  ]
}
EOF
)
  CMD="unset HISTFILE\n
if [ -f /tmp/realm.json ]; then\n
  echo \"WARNING: Found existing realm configuration file in the container. May be from a previous install. Skipping configuration.\"\n
  exit 0\n
fi\n
cat >/tmp/realm.json <<EOF\n$(echo -e "$REALM_JSON")\nEOF\n
while true; do\n
  STATUS=\$(curl -ifs http://localhost:8080/ 2>/dev/null | head -1)\n
  if [[ ! -z \"\$STATUS\" ]] && [[ \"\$STATUS\" == *\"200\"* ]]; then\n
    cd /opt/bitnami/keycloak/bin\n
    ./kcadm.sh config credentials --server http://localhost:8080/ --realm master --user admin --password \"$KEYCLOAK_ADMIN_PASSWORD\" --config /tmp/kcadm.config\n
    ./kcadm.sh update realms/master -s sslRequired=NONE --config /tmp/kcadm.config\n
    ./kcadm.sh create realms -f /tmp/realm.json --config /tmp/kcadm.config\n
    USER_ID=\$(./kcadm.sh get users -r $KEYCLOAK_REALM -q username=alice --fields id --config /tmp/kcadm.config 2>/dev/null | cut -d' ' -f5 | cut -d'\"' -f2 | tr -d '\\\n')\n
    ./kcadm.sh update users/\$USER_ID -r $KEYCLOAK_REALM -s 'credentials=[{\"type\":\"password\",\"value\":\"$KEYCLOAK_USER_ALICE_PASSWORD\"}]' --config /tmp/kcadm.config\n
    USER_ID=\$(./kcadm.sh get users -r $KEYCLOAK_REALM -q username=bob --fields id --config /tmp/kcadm.config 2>/dev/null | cut -d' ' -f5 | cut -d'\"' -f2 | tr -d '\\\n')\n
    ./kcadm.sh update users/\$USER_ID -r $KEYCLOAK_REALM -s 'credentials=[{\"type\":\"password\",\"value\":\"$KEYCLOAK_USER_BOB_PASSWORD\"}]' --config /tmp/kcadm.config\n
    USER_ID=\$(./kcadm.sh get users -r $KEYCLOAK_REALM -q username=charlie --fields id --config /tmp/kcadm.config 2>/dev/null | cut -d' ' -f5 | cut -d'\"' -f2 | tr -d '\\\n')\n
    ./kcadm.sh update users/\$USER_ID -r $KEYCLOAK_REALM -s 'credentials=[{\"type\":\"password\",\"value\":\"$KEYCLOAK_USER_CHARLIE_PASSWORD\"}]' --config /tmp/kcadm.config\n
    break\n
  fi\n
  echo \"Keycloak admin server not available. Waiting for 10 seconds...\"\n
  sleep 10\n
done;"
  echo "Checking keycloak pod status..."
  POD_PHASE=$(kubectl get pod keycloak-0 -n keycloak -o jsonpath='{.status.phase}')
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to check keycloak pod status."
  fi
  while [ "$POD_PHASE" != "Running" ]
  do
    echo "Keycloak pod status is '$POD_PHASE'. Waiting for 10 seconds."
    sleep 10
    POD_PHASE=$(kubectl get pod keycloak-0 -n keycloak -o jsonpath='{.status.phase}')
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to check keycloak pod status."
    fi
  done
  kubectl exec -it keycloak-0 -n keycloak -- /bin/bash -c "$(echo -e "$CMD")"
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to configure keycloak."
  fi
}

function wait_for_load_balancer() {
  echo "Checking Target Group health..."

  LB_ARN=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerArn, `loadbalancer/net/k8s-keycloak-keycloak-`)].LoadBalancerArn' --output text)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to describe keycloak load balancer."
  fi

  TARGET_GRP_ARN=$(aws elbv2 describe-target-groups --load-balancer-arn "$LB_ARN" --query 'TargetGroups[0].TargetGroupArn' --output text)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to describe keycloak target group."
  fi

  TARGET_HEALTH=$(aws elbv2 describe-target-health --target-group-arn "$TARGET_GRP_ARN" --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to describe keycloak target health."
  fi

  while [ "$TARGET_HEALTH" != "healthy" ]
  do
    echo "Target health is $TARGET_HEALTH. Waiting 10 seconds."
    sleep 10
    TARGET_HEALTH=$(aws elbv2 describe-target-health --target-group-arn "$TARGET_GRP_ARN" --query 'TargetHealthDescriptions[0].TargetHealth.State' --output text)
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to describe keycloak target health."
    fi
  done

  echo "Target health is $TARGET_HEALTH."

  ELB_HOSTNAME=$(kubectl get service/keycloak \
    -n "$KEYCLOAK_NAMESPACE" \
    --output go-template \
    --template='{{range .status.loadBalancer.ingress}}{{.hostname}}{{end}}')
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to get load balancer hostname."
  fi
}

function download_oidc_configuration() {
  OIDC_CONFIG=$(curl -s "http://${ELB_HOSTNAME}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration")
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to download OIDC configuration from ${OIDC_CONFIG}."
  fi
}

#### Main ####

handle_arg_help

resolve_arg_account_id

validate_arg_cluster_name

resolve_arg_keycloak_namespace

resolve_arg_keycloak_realm

print_script_arguments

locate_eks_cluster

install_ebs_csi_driver

check_helm

add_helm_repo "external-secrets" "https://charts.external-secrets.io"

install_external_secrets

configure_keycloak_password

configure_keycloak_externalsecret

add_helm_repo "bitnami" "https://charts.bitnami.com/bitnami"

install_keycloak

configure_keycloak

wait_for_load_balancer

download_oidc_configuration

echo ""
echo "Keycloak setup done."
echo ""
echo "--------------------------------------"
echo "Next Steps"
echo "--------------------------------------"
echo "This setup script has created a new realm in Keycloak for Istio authentication."
echo ""
echo "The realm contains the following resources:"
echo " - three application roles,"
echo " - three application users that are assigned to each of the roles respectively and"
echo " - an OIDC client for 'productapp' application."
echo ""
echo "The user and role assignments are shown below:"
printf "+ ---------- + ---------- +\n"
printf "| %-10s | %-10s |\n" "User" "Role"
printf "+ ---------- + ---------- +\n"
printf "| %-10s | %-10s |\n" "alice" "guest"
printf "| %-10s | %-10s |\n" "bob" "admin"
printf "| %-10s | %-10s |\n" "charlie" "other"
printf "+ ---------- + ---------- +\n"
echo ""
echo "A helper script ('bin/04-keycloak-helpers.sh') is provided to easily interact with Keycloak and configure Istio request authentication resources."
echo "Below are some examples of using the helper script to perform various actions related to configuring Istio request authentication."
echo ""
echo "Examples:"
echo "---------"
echo " - Generate access token for application user 'alice':"
echo "   $ bin/04-keycloak-helpers.sh -g -u alice"
echo ""
echo " - Inspect generated access token:"
echo "   $ bin/04-keycloak-helpers.sh -i -t <TOKEN>"
echo ""
echo " - Apply RequestAuthentication manifest:"
echo "   $ bin/04-keycloak-helpers.sh --authn"
echo ""
echo " - Apply AuthorizationPolicy manifest:"
echo "   $ bin/04-keycloak-helpers.sh --authz"
echo ""
echo " - Print Keycloak admin console URL:"
echo "   $ bin/04-keycloak-helpers.sh -c"
echo ""
echo " - Print Keycloak admin user password:"
echo "   $ bin/04-keycloak-helpers.sh -a"
echo ""
echo "Clean up:"
echo "---------"
echo "Once done experimenting with Keycloak integration use the provided clean up script ('bin/04-keycloak-cleanup.sh') to clean up all the Kubernetes and AWS resources created by this script."
echo "--------------------------------------"