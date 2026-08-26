#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
MODE="${2:-}"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BICEP_FILE="$ROOT_DIR/infrastructure/bicep/main.bicep"
BOOTSTRAP_BICEP_FILE="$ROOT_DIR/infrastructure/bootstrap/main.bicep"
PARAM_FILE="$ROOT_DIR/infrastructure/bicep/main.parameters.json"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-voxa-${ENVIRONMENT}}"
LOCATION="${AZURE_LOCATION:-swedencentral}"

cd "$ROOT_DIR"

bash ./infrastructure/scripts/guard-tests.sh
az bicep build --file "$BOOTSTRAP_BICEP_FILE"
az bicep build --file "$BICEP_FILE"

if [ "$MODE" = "--lint-only" ]; then
  echo "Bicep lint/build completed."
  exit 0
fi

if [ "$MODE" = "--what-if" ]; then
  az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$BICEP_FILE" \
    --parameters "$PARAM_FILE" \
    --parameters environmentName="$ENVIRONMENT" location="$LOCATION" openAiApiKey="${OPENAI_API_KEY:-set-in-github-actions}"
  exit 0
fi

az deployment group validate \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$BICEP_FILE" \
  --parameters "$PARAM_FILE" \
  --parameters environmentName="$ENVIRONMENT" location="$LOCATION" openAiApiKey="${OPENAI_API_KEY:-set-in-github-actions}"
