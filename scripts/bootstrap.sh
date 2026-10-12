#!/usr/bin/env bash
# One-time setup, run with the Azure CLI after `az login` (as Owner of the subscription):
#   1. Resource group + storage account + container for Terraform remote state
#   2. Entra app registration with GitHub OIDC federated credentials (no stored secrets)
#   3. Role assignments for that app
#
# Usage:  GH_REPO=<owner>/<repo> ./scripts/bootstrap.sh
set -euo pipefail

# Git Bash on Windows rewrites arguments that start with "/" (such as /subscriptions/...) into
# Windows paths. Turn that off so the Azure CLI receives resource IDs unchanged.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

: "${GH_REPO:?Set GH_REPO=<owner>/<repo>, for example GH_REPO=pobournex/azure-incident-tracker}"
LOCATION="${LOCATION:-centralus}"
STATE_RG="${STATE_RG:-rg-tfstate}"
APP_NAME="${APP_NAME:-gh-oidc-incident-tracker}"
CONTAINER="tfstate"

SUB_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
# Storage account names are global, 3-24 lowercase letters and digits.
STATE_SA="${STATE_SA:-sttf$(echo "$SUB_ID" | tr -d '-' | cut -c1-14)}"

echo "Subscription: $SUB_ID"
echo "State account: $STATE_SA (resource group $STATE_RG, $LOCATION)"

# ---- 1. Terraform state backend ----
az group create --name "$STATE_RG" --location "$LOCATION" --tags project=incident-tracker purpose=tfstate -o none
az storage account create \
  --name "$STATE_SA" --resource-group "$STATE_RG" --location "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false -o none
STATE_SA_ID="$(az storage account show --name "$STATE_SA" --resource-group "$STATE_RG" --query id -o tsv)"

ME="$(az ad signed-in-user show --query id -o tsv)"
az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$STATE_SA_ID" -o none || true
echo "Waiting for role assignment to propagate..."
sleep 45
az storage container create --name "$CONTAINER" --account-name "$STATE_SA" --auth-mode login -o none

# ---- 2. Entra app + GitHub OIDC federation ----
APP_ID="$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)"
if [ -z "$APP_ID" ]; then
  APP_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
  az ad sp create --id "$APP_ID" -o none
fi

add_federated_credential() {
  local name="$1" subject="$2"
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp" <<EOF
{"name":"$name","issuer":"https://token.actions.githubusercontent.com","subject":"$subject","audiences":["api://AzureADTokenExchange"]}
EOF
  # The Windows Azure CLI cannot read Git Bash style /tmp paths; convert when cygpath exists.
  local tmp_arg="$tmp"
  if command -v cygpath >/dev/null 2>&1; then tmp_arg="$(cygpath -w "$tmp")"; fi
  az ad app federated-credential create --id "$APP_ID" --parameters "$tmp_arg" -o none 2>/dev/null \
    && echo "Created federated credential: $name" \
    || echo "Federated credential $name already exists (or could not be created)"
  rm -f "$tmp"
}

add_federated_credential gh-main        "repo:${GH_REPO}:ref:refs/heads/main"
add_federated_credential gh-pr          "repo:${GH_REPO}:pull_request"
add_federated_credential gh-env-apply   "repo:${GH_REPO}:environment:azure-apply"
add_federated_credential gh-env-destroy "repo:${GH_REPO}:environment:azure-destroy"
add_federated_credential gh-env-deploy  "repo:${GH_REPO}:environment:azure-deploy"

# ---- 3. Roles for the pipeline identity ----
SP_OBJECT_ID="$(az ad sp show --id "$APP_ID" --query id -o tsv)"
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal \
  --role "Contributor" --scope "/subscriptions/$SUB_ID" -o none || true
az role assignment create --assignee-object-id "$SP_OBJECT_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$STATE_SA_ID" -o none || true

cat <<EOF

Done. Add these as GitHub repository VARIABLES (Settings > Secrets and variables > Actions > Variables):
  AZURE_CLIENT_ID        = $APP_ID
  AZURE_TENANT_ID        = $TENANT_ID
  AZURE_SUBSCRIPTION_ID  = $SUB_ID
  TFSTATE_RESOURCE_GROUP = $STATE_RG
  TFSTATE_STORAGE_ACCOUNT= $STATE_SA
  (optional) ALLOWED_SSH_CIDR = leave unset to keep SSH closed; deploys open a temporary rule

And these as repository SECRETS:
  ADMIN_SSH_PUBLIC_KEY   = contents of your .pub key
  ANSIBLE_SSH_PRIVATE_KEY= matching private key (used by the deploy workflow)
  ANSIBLE_VAULT_PASSWORD = password for ansible/inventory/group_vars/all/vault.yml

Create GitHub Environments named: azure-apply, azure-destroy, azure-deploy (add yourself as required reviewer on azure-apply and azure-destroy).
EOF
