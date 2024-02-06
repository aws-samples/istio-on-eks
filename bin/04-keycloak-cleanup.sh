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

#title           04-keycloak-cleanup.sh
#description     This script cleans up keycloak related resources for Istio request authentication.
#author          Sourav Paul (@psour)
#contributors    @psour
#date            2024-01-19
#version         1.0
#usage           ./04-keycloak-cleanup.sh -c <EKS_CLUSTER_NAME> [-a|--account-id <ACCOUNT_ID>] [-n|--keycloak-namespace <KEYCLOAK_NAMESPACE>] [-h|--help]
#==============================================================================

echo ---------------------------------------------------------------------------------------------
echo "This script cleans up keycloak related resources for Istio request authentication."
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
  echo "    -h, --help                         Show this help message"
}

function handle_error() {
  echo ""
  echo $1
  exit 1
}

function handle_error_with_usage() {
  echo ""
  echo $1
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

function print_script_arguments() {
  echo ""
  echo "Script arguments:"
  echo "---------------------------------------------------------------------------------------------"
  echo "  ACCOUNT_ID..........$ACCOUNT_ID"
  echo "  CLUSTER_NAME........$CLUSTER_NAME"
  echo "  KEYCLOAK_NAMESPACE..$KEYCLOAK_NAMESPACE"
  echo "---------------------------------------------------------------------------------------------"
  echo ""
}

function locate_eks_cluster() {
  echo "Searching Amazon EKS cluster with name '$CLUSTER_NAME'..."
  CLUSTER_META=$(aws eks describe-cluster --name $CLUSTER_NAME)
  CMD_RESULT=$?
  if [ -z "$CLUSTER_META" ] || [ $CMD_RESULT -ne 0 ] ; then
    handle_error "ERROR: Could not locate Amazon EKS cluster with name '$CLUSTER_NAME'. Please check error message."
  fi
  echo "Found Amazon EKS cluster."
}

function uninstall_keycloak() {
  echo "Uninstalling application 'keycloak'..."
  CMD_OUT=$(helm uninstall keycloak --namespace $KEYCLOAK_NAMESPACE 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *"not found"* )
        ;;
      *)
        handle_error "ERROR: Failed to uninstall application 'keycloak'."
        ;;
    esac
  fi
}

function delete_iam_role_for_sa() {
  ROLE_NAME="$1"
  POLICY_ARN="$2"

  echo "Detaching IAM policy ${POLICY_ARN} from role ${ROLE_NAME}..."
  CMD_OUT=$(aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" --output text 2>&1)
  CMD_RESULT=$?
  if [[ $CMD_OUT == *"(NoSuchEntity)"* ]]; then
    echo "Nothing to detach. Skipping detach."
  elif [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to detach IAM policy ${POLICY_ARN} from role ${ROLE_NAME}. Detailed error: ${CMD_OUT}"
  else
    echo "Successfully detached IAM policy ${POLICY_ARN} from role ${ROLE_NAME}."
  fi

  echo "Deleting IAM role ${ROLE_NAME}..."
  CMD_OUT=$(aws iam delete-role --role-name "$ROLE_NAME" --output text 2>&1)
  CMD_RESULT=$?
  if [[ $CMD_OUT == *"(NoSuchEntity)"* ]]; then
    echo "IAM role ${ROLE_NAME} not found. Skipping delete."
  elif [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to delete IAM role ${ROLE_NAME}. Detailed error: ${CMD_OUT}"
  else
    echo "IAM role ${ROLE_NAME} deleted."
  fi
}

function delete_sa() {
  NAMESPACE="$1"
  SERVICE_ACCOUNT_NAME="$2"

  echo "Deleting service account ${SERVICE_ACCOUNT_NAME} in namespace ${NAMESPACE}..."
  CMD_OUT=$(kubectl delete sa "$SERVICE_ACCOUNT_NAME" -n "$NAMESPACE" 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *NotFound* )
        ;;
      *)
        handle_error "ERROR: Failed to delete service account ${SERVICE_ACCOUNT_NAME} in namespace ${NAMESPACE}."
        ;;
    esac
  fi

  echo "Service account ${SERVICE_ACCOUNT_NAME} in namespace ${NAMESPACE} deleted successfully."
}

function delete_keycloak_secrets() {
  echo "Deleting Keycloak ExternalSecret..."
  CMD_OUT=$(kubectl delete ExternalSecret keycloak -n $KEYCLOAK_NAMESPACE 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *"doesn't"* | *NotFound* )
        ;;
      *)
        handle_error "ERROR: Failed to delete Keycloak ExternalSecret."
        ;;
    esac
  fi
  echo "Deleting Keycloak SecretStore..."
  CMD_OUT=$(kubectl delete SecretStore keycloak -n $KEYCLOAK_NAMESPACE 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *"doesn't"* | *NotFound* )
        ;;
      *)
        handle_error "ERROR: Failed to delete Keycloak SecretStore."
        ;;
    esac
  fi
  
  echo "Deleting IRSA for Keycloak SecretStore..."
  delete_sa \
    "$KEYCLOAK_NAMESPACE" \
    "keycloaksecretstore"
  
  POLICY_NAME=istio-keycloak-secretstore-policy
  delete_iam_role_for_sa \
    "istio-keycloak-secretstore-role" \
    "arn:aws:iam::$ACCOUNT_ID:policy/${POLICY_NAME}"

  sleep 10
  echo "Deleting IAM policy for Keycloak SecretStore..."
  CMD_OUT=$(aws iam delete-policy --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/${POLICY_NAME}" 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    echo $CMD_OUT
    case "$CMD_OUT" in
      *NoSuchEntity* )
        ;;
      *)
        handle_error "ERROR: Failed to delete IAM policy for Keycloak SecretStore."
        ;;
    esac
  fi
  
  echo "Deleting namespace '$KEYCLOAK_NAMESPACE'..."
  CMD_OUT=$(kubectl delete ns $KEYCLOAK_NAMESPACE 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *"doesn't"* | *NotFound* )
        ;;
      *)
        handle_error "ERROR: Failed to delete namespce '$KEYCLOAK_NAMESPACE'."
        ;;
    esac
  fi
  
  echo "Checking saved keycloak password in AWS Secrets Manager..."
  SECRET_NAME="istio/keycloak"
  SECRET_ARN=$(aws secretsmanager list-secrets --filters Key=name,Values=$SECRET_NAME Key=tag-key,Values=Project Key=tag-value,Values=Istio-on-EKS --query "SecretList[0].ARN" --output text)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to check saved keycloak password in AWS Secrets Manager."
  fi
  if [ "$SECRET_ARN" != "None" ]; then
    echo "Found saved keycloak password. Deleting saved value..."
    DELETE_SECRET_RESPONSE=$(aws secretsmanager delete-secret --secret-id $SECRET_ARN --force-delete-without-recovery 2>&1)
    CMD_RESULT=$?
    if [ $CMD_RESULT -ne 0 ]; then
      handle_error "ERROR: Failed to delete saved keycloak password from AWS Secrets Manager. Detailed error response: ${DELETE_SECRET_RESPONSE}"
    fi
  fi
}

function uninstall_external_secrets() {
  echo "Uninstalling application 'external-secrets'..."
  CMD_OUT=$(helm uninstall external-secrets --namespace external-secrets 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *"not found"* )
        ;;
      *)
        handle_error "ERROR: Failed to uninstall application 'external-secrets'."
        ;;
    esac
  fi
  
  echo "Deleting namespace 'external-secrets'..."
  CMD_OUT=$(kubectl delete ns external-secrets 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *"doesn't"* | *NotFound* )
        ;;
      *)
        handle_error "ERROR: Failed to delete namespce 'external-secrets'."
        ;;
    esac
  fi
}

function remove_helm_repo() {
  REPO=$1
  echo "Removing helm repo '$REPO'..."
  CMD_OUT=$(helm repo remove $REPO 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *"no repo"* )
        ;;
      *)
        handle_error "ERROR: Failed to remove helm repo '$REPO'."
        ;;
    esac
  fi
}

function uninstall_ebs_csi_driver_addon() {
  echo "Deleting EBS StorageClass..."
  CMD_OUT=$(kubectl delete StorageClass ebs-sc 2>&1)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *"NotFound"* )
        ;;
      *)
        handle_error "ERROR: Failed to delete EBS StorageClass 'ebs-sc'."
        ;;
    esac
  fi

  echo "Uninstalling EBS CSI driver addon from cluster..."
  CMD_OUT=$(aws eks delete-addon \
    --addon-name aws-ebs-csi-driver \
    --cluster-name "$CLUSTER_NAME" 2>&1 > /dev/null)
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    case "$CMD_OUT" in
      *"ResourceNotFoundException"* )
        ;;
      *)
        handle_error "ERROR: Failed to uninstall EBS CSI driver addon from cluster."
        ;;
    esac
  fi

  echo "Waiting for EBS CSI driver addon deletion to complete..."
  aws eks wait addon-deleted \
    --cluster-name $CLUSTER_NAME \
    --addon-name aws-ebs-csi-driver
  CMD_RESULT=$?
  if [ $CMD_RESULT -ne 0 ]; then
    handle_error "ERROR: Failed to wait for EBS CSI driver addon deletion to complete."
  fi

  echo "Deleting IRSA for EBS CSI driver addon..."
  delete_sa \
    "kube-system" \
    "ebs-csi-controller-sa"
  
  delete_iam_role_for_sa \
    "istio-eks-ebs-csi-driver-role" \
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

#### Main ####

handle_arg_help

resolve_arg_account_id

validate_arg_cluster_name

resolve_arg_keycloak_namespace

print_script_arguments

locate_eks_cluster

uninstall_keycloak

delete_keycloak_secrets

remove_helm_repo "bitnami"

uninstall_external_secrets

remove_helm_repo "external-secrets"

uninstall_ebs_csi_driver_addon

echo ""
echo "Cleanup done."