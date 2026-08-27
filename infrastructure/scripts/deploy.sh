#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BICEP_FILE="$ROOT_DIR/infrastructure/bicep/main.bicep"
NETWORK_BICEP_FILE="$ROOT_DIR/infrastructure/bicep/network.bicep"
PARAM_FILE="$ROOT_DIR/infrastructure/bicep/main.parameters.json"
NETWORK_PARAM_FILE="$ROOT_DIR/infrastructure/bicep/network.parameters.json"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-voxa-${ENVIRONMENT}}"
NETWORK_RESOURCE_GROUP="${AZURE_NETWORK_RESOURCE_GROUP:-rg-voxa-network-${ENVIRONMENT}}"
LOCATION="${AZURE_LOCATION:-swedencentral}"

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "OPENAI_API_KEY is required for deployment." >&2
  exit 1
fi

cd "$ROOT_DIR"

bash ./infrastructure/scripts/validate.sh "$ENVIRONMENT" --lint-only

az deployment group create \
  --name "network-${ENVIRONMENT}" \
  --resource-group "$NETWORK_RESOURCE_GROUP" \
  --template-file "$NETWORK_BICEP_FILE" \
  --parameters "$NETWORK_PARAM_FILE" \
  --parameters environmentName="$ENVIRONMENT" location="$LOCATION"

az deployment group create \
  --name "main" \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$BICEP_FILE" \
  --parameters "$PARAM_FILE" \
  --parameters environmentName="$ENVIRONMENT" location="$LOCATION" openAiApiKey="$OPENAI_API_KEY" networkResourceGroupName="$NETWORK_RESOURCE_GROUP"
