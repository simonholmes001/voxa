#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-simonholmes001/voxa}"
GITHUB_REF="${GITHUB_REF:-refs/heads/main}"
GITHUB_OWNER_ID="${GITHUB_OWNER_ID:-31061938}"
GITHUB_REPO_ID="${GITHUB_REPO_ID:-1347555953}"
LOCATION="${AZURE_LOCATION:-swedencentral}"
SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
PIPELINE_RG="${AZURE_PIPELINE_RESOURCE_GROUP:-rg-voxa-pipeline-identity}"
TARGET_RG="${AZURE_RESOURCE_GROUP:-rg-voxa-${ENVIRONMENT}}"
IDENTITY_NAME="${AZURE_PIPELINE_IDENTITY_NAME:-id-voxa-github-actions}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP_BICEP_FILE="$ROOT_DIR/infrastructure/bootstrap/main.bicep"

if [ -z "$SUBSCRIPTION_ID" ]; then
  echo "AZURE_SUBSCRIPTION_ID is required." >&2
  exit 1
fi

GITHUB_ORG="${GITHUB_REPOSITORY%%/*}"
GITHUB_REPO="${GITHUB_REPOSITORY#*/}"

az account set --subscription "$SUBSCRIPTION_ID"

az deployment sub create \
  --name "voxa-bootstrap-${ENVIRONMENT}" \
  --location "$LOCATION" \
  --template-file "$BOOTSTRAP_BICEP_FILE" \
  --parameters \
    environmentName="$ENVIRONMENT" \
    location="$LOCATION" \
    githubOrg="$GITHUB_ORG" \
    githubOrgId="$GITHUB_OWNER_ID" \
    githubRepo="$GITHUB_REPO" \
    githubRepoId="$GITHUB_REPO_ID" \
    githubRef="$GITHUB_REF" \
    pipelineResourceGroupName="$PIPELINE_RG" \
    targetResourceGroupName="$TARGET_RG" \
    pipelineIdentityName="$IDENTITY_NAME" \
  --query properties.outputs

echo
echo "Copy these output values into repository secrets:"
echo "AZURE_CLIENT_ID      = azureClientId.value"
echo "AZURE_TENANT_ID      = azureTenantId.value"
echo "AZURE_SUBSCRIPTION_ID= azureSubscriptionId.value"
echo "AZURE_LOCATION       = azureLocation.value"
echo "AZURE_RESOURCE_GROUP = azureResourceGroup.value"
