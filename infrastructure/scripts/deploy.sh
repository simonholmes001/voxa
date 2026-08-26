#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BICEP_FILE="$ROOT_DIR/infrastructure/bicep/main.bicep"
PARAM_FILE="$ROOT_DIR/infrastructure/bicep/main.parameters.json"
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-voxa-${ENVIRONMENT}}"
LOCATION="${AZURE_LOCATION:-swedencentral}"

if [ -z "${OPENAI_API_KEY:-}" ]; then
  echo "OPENAI_API_KEY is required for deployment." >&2
  exit 1
fi

cd "$ROOT_DIR"

bash ./infrastructure/scripts/validate.sh "$ENVIRONMENT" --lint-only

az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file "$BICEP_FILE" \
  --parameters "$PARAM_FILE" \
  --parameters environmentName="$ENVIRONMENT" location="$LOCATION" openAiApiKey="$OPENAI_API_KEY"
