#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-simonholmes001/voxa}"
LOCATION="${AZURE_LOCATION:-westeurope}"
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
PIPELINE_RG="${AZURE_PIPELINE_RESOURCE_GROUP:-rg-voxa-pipeline-identity}"
TARGET_RG="${AZURE_RESOURCE_GROUP:-rg-voxa-${ENVIRONMENT}}"
IDENTITY_NAME="${AZURE_PIPELINE_IDENTITY_NAME:-id-voxa-github-actions}"

if [ -z "$SUBSCRIPTION_ID" ]; then
  echo "AZURE_SUBSCRIPTION_ID is required." >&2
  exit 1
fi

az account set --subscription "$SUBSCRIPTION_ID"

az group show --name "$PIPELINE_RG" >/dev/null 2>&1 || \
  az group create --name "$PIPELINE_RG" --location "$LOCATION" --tags application=voxa purpose=pipeline-identity --yes >/dev/null

az identity show --resource-group "$PIPELINE_RG" --name "$IDENTITY_NAME" >/dev/null 2>&1 || \
  az identity create --resource-group "$PIPELINE_RG" --name "$IDENTITY_NAME" --location "$LOCATION" --tags application=voxa purpose=github-actions >/dev/null

CLIENT_ID="$(az identity show --resource-group "$PIPELINE_RG" --name "$IDENTITY_NAME" --query clientId -o tsv)"
PRINCIPAL_ID="$(az identity show --resource-group "$PIPELINE_RG" --name "$IDENTITY_NAME" --query principalId -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"

az group show --name "$TARGET_RG" >/dev/null 2>&1 || \
  az group create --name "$TARGET_RG" --location "$LOCATION" --tags application=voxa environment="$ENVIRONMENT" managedBy=bicep costProfile=minimal --yes >/dev/null

SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${TARGET_RG}"
if ! az role assignment list --assignee "$PRINCIPAL_ID" --scope "$SCOPE" --query "[?roleDefinitionName=='Contributor'] | length(@)" -o tsv | grep -q '^1$'; then
  az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role Contributor --scope "$SCOPE" >/dev/null
fi

FEDERATED_NAME="github-${ENVIRONMENT}"
SUBJECT="repo:${GITHUB_REPOSITORY}:environment:${ENVIRONMENT}"
if ! az identity federated-credential show --resource-group "$PIPELINE_RG" --identity-name "$IDENTITY_NAME" --name "$FEDERATED_NAME" >/dev/null 2>&1; then
  az identity federated-credential create \
    --resource-group "$PIPELINE_RG" \
    --identity-name "$IDENTITY_NAME" \
    --name "$FEDERATED_NAME" \
    --issuer "https://token.actions.githubusercontent.com" \
    --subject "$SUBJECT" \
    --audiences "api://AzureADTokenExchange" >/dev/null
fi

cat <<EOF
Azure OIDC pipeline identity configured.

Set these GitHub environment variables for '${ENVIRONMENT}':
AZURE_CLIENT_ID=${CLIENT_ID}
AZURE_TENANT_ID=${TENANT_ID}
AZURE_SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
AZURE_LOCATION=${LOCATION}
AZURE_RESOURCE_GROUP=${TARGET_RG}
EOF
