#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
MODE="${2:-}"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BICEP_FILE="$ROOT_DIR/infrastructure/bicep/main.bicep"
NETWORK_BICEP_FILE="$ROOT_DIR/infrastructure/bicep/network.bicep"
PRIVATE_ENDPOINTS_BICEP_FILE="$ROOT_DIR/infrastructure/bicep/private-endpoints.bicep"
BOOTSTRAP_BICEP_FILE="$ROOT_DIR/infrastructure/bootstrap/main.bicep"
PARAM_FILE="$ROOT_DIR/infrastructure/bicep/main.parameters.json"
NETWORK_PARAM_FILE="$ROOT_DIR/infrastructure/bicep/network.parameters.json"
PRIVATE_ENDPOINTS_PARAM_FILE="$ROOT_DIR/infrastructure/bicep/private-endpoints.parameters.json"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-voxa-${ENVIRONMENT}}"
NETWORK_RESOURCE_GROUP="${AZURE_NETWORK_RESOURCE_GROUP:-rg-voxa-network-${ENVIRONMENT}}"
LOCATION="${AZURE_LOCATION:-swedencentral}"

cd "$ROOT_DIR"

bash ./infrastructure/scripts/guard-tests.sh
az bicep build --file "$BOOTSTRAP_BICEP_FILE"
az bicep build --file "$NETWORK_BICEP_FILE"
az bicep build --file "$BICEP_FILE"
az bicep build --file "$PRIVATE_ENDPOINTS_BICEP_FILE"

if [ "$MODE" = "--lint-only" ]; then
  echo "Bicep lint/build completed."
  exit 0
fi

if [ "$MODE" = "--what-if" ]; then
  az deployment group what-if \
    --name "network-${ENVIRONMENT}" \
    --resource-group "$NETWORK_RESOURCE_GROUP" \
    --template-file "$NETWORK_BICEP_FILE" \
    --parameters "$NETWORK_PARAM_FILE" \
    --parameters environmentName="$ENVIRONMENT" location="$LOCATION"

  az deployment group what-if \
    --name "main" \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$BICEP_FILE" \
    --parameters "$PARAM_FILE" \
    --parameters environmentName="$ENVIRONMENT" location="$LOCATION" openAiApiKey="${OPENAI_API_KEY:-set-in-github-actions}" appSessionSigningKey="${APP_SESSION_SIGNING_KEY:-validation-signing-key-32-bytes-minimum}" appleClientId="${APPLE_CLIENT_ID:-com.simonholmes.voxa}" appleTeamId="${APPLE_TEAM_ID:-2PA85SU4UQ}" appleKeyId="${APPLE_KEY_ID:-APPLEKEYID1}" applePrivateKey="${APPLE_PRIVATE_KEY:-validation-apple-private-key-placeholder-not-for-deploy}" networkResourceGroupName="$NETWORK_RESOURCE_GROUP"

  az deployment group what-if \
    --name "private-endpoints-${ENVIRONMENT}" \
    --resource-group "$NETWORK_RESOURCE_GROUP" \
    --template-file "$PRIVATE_ENDPOINTS_BICEP_FILE" \
    --parameters "$PRIVATE_ENDPOINTS_PARAM_FILE" \
    --parameters environmentName="$ENVIRONMENT" location="$LOCATION" workloadResourceGroupName="$RESOURCE_GROUP"
  exit 0
fi

az deployment group validate \
  --name "network-${ENVIRONMENT}" \
  --resource-group "$NETWORK_RESOURCE_GROUP" \
  --template-file "$NETWORK_BICEP_FILE" \
  --parameters "$NETWORK_PARAM_FILE" \
  --parameters environmentName="$ENVIRONMENT" location="$LOCATION"

az deployment group validate \
  --name "main" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$BICEP_FILE" \
  --parameters "$PARAM_FILE" \
  --parameters environmentName="$ENVIRONMENT" location="$LOCATION" openAiApiKey="${OPENAI_API_KEY:-set-in-github-actions}" appSessionSigningKey="${APP_SESSION_SIGNING_KEY:-validation-signing-key-32-bytes-minimum}" appleClientId="${APPLE_CLIENT_ID:-com.simonholmes.voxa}" appleTeamId="${APPLE_TEAM_ID:-2PA85SU4UQ}" appleKeyId="${APPLE_KEY_ID:-APPLEKEYID1}" applePrivateKey="${APPLE_PRIVATE_KEY:-validation-apple-private-key-placeholder-not-for-deploy}" networkResourceGroupName="$NETWORK_RESOURCE_GROUP"

az deployment group validate \
  --name "private-endpoints-${ENVIRONMENT}" \
  --resource-group "$NETWORK_RESOURCE_GROUP" \
  --template-file "$PRIVATE_ENDPOINTS_BICEP_FILE" \
  --parameters "$PRIVATE_ENDPOINTS_PARAM_FILE" \
  --parameters environmentName="$ENVIRONMENT" location="$LOCATION" workloadResourceGroupName="$RESOURCE_GROUP"
