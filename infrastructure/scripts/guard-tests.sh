#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BICEP_FILE="$ROOT_DIR/infrastructure/bicep/main.bicep"

[ -f "$BICEP_FILE" ] || { echo "Missing $BICEP_FILE" >&2; exit 1; }

grep -q "FlexConsumption" "$BICEP_FILE" || { echo "Function plan must use Flex Consumption." >&2; exit 1; }
grep -q "UserAssigned" "$BICEP_FILE" || { echo "Function app must use user-assigned managed identity." >&2; exit 1; }
grep -q "allowSharedKeyAccess: false" "$BICEP_FILE" || { echo "Storage local auth must be disabled." >&2; exit 1; }
grep -q "allowBlobPublicAccess: false" "$BICEP_FILE" || { echo "Storage blob public access must be disabled." >&2; exit 1; }
grep -q "enableRbacAuthorization: true" "$BICEP_FILE" || { echo "Key Vault must use RBAC authorization." >&2; exit 1; }
grep -q "publicNetworkAccess: 'Enabled'" "$BICEP_FILE" || { echo "Key Vault public network access must be explicitly enabled for MVP." >&2; exit 1; }
grep -q "diagnosticSettings" "$BICEP_FILE" || { echo "Function diagnostics must be configured." >&2; exit 1; }
grep -q "0.0.0.0" "$BICEP_FILE" || { echo "Cosmos Azure Services firewall rule must be present when Cosmos is enabled." >&2; exit 1; }

if grep -q "Microsoft.ContainerRegistry" "$BICEP_FILE"; then
  echo "ACR must not be part of the MVP baseline." >&2
  exit 1
fi

echo "Infrastructure guard tests passed."
