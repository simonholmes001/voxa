#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BICEP_FILE="$ROOT_DIR/infrastructure/bicep/main.bicep"
BOOTSTRAP_BICEP_FILE="$ROOT_DIR/infrastructure/bootstrap/main.bicep"

[ -f "$BICEP_FILE" ] || { echo "Missing $BICEP_FILE" >&2; exit 1; }
[ -f "$BOOTSTRAP_BICEP_FILE" ] || { echo "Missing $BOOTSTRAP_BICEP_FILE" >&2; exit 1; }

grep -q "FlexConsumption" "$BICEP_FILE" || { echo "Function plan must use Flex Consumption." >&2; exit 1; }
grep -q "UserAssigned" "$BICEP_FILE" || { echo "Function app must use user-assigned managed identity." >&2; exit 1; }
grep -q "allowSharedKeyAccess: false" "$BICEP_FILE" || { echo "Storage local auth must be disabled." >&2; exit 1; }
grep -q "allowBlobPublicAccess: false" "$BICEP_FILE" || { echo "Storage blob public access must be disabled." >&2; exit 1; }
grep -q "enableRbacAuthorization: true" "$BICEP_FILE" || { echo "Key Vault must use RBAC authorization." >&2; exit 1; }
grep -q "param enablePrivateNetworking bool = true" "$BICEP_FILE" || { echo "Private networking must be enabled by default." >&2; exit 1; }
grep -q "param allowPublicNetworkAccessForDev bool = false" "$BICEP_FILE" || { echo "Public network access escape hatch must default to false." >&2; exit 1; }
grep -q "param enablePrivateFunctionIngress bool = false" "$BICEP_FILE" || { echo "Function private ingress must be an explicit opt-in for the mobile MVP." >&2; exit 1; }
grep -q "publicNetworkAccess: publicNetworkAccessValue" "$BICEP_FILE" || { echo "Data resources must use the private-network public access guard." >&2; exit 1; }
grep -q "publicNetworkAccess: functionPublicNetworkAccessValue" "$BICEP_FILE" || { echo "Function ingress must use an explicit public/private access guard." >&2; exit 1; }
grep -q "Microsoft.Network/virtualNetworks" "$BICEP_FILE" || { echo "A VNet must be part of the private networking baseline." >&2; exit 1; }
grep -q "Microsoft.App/environments" "$BICEP_FILE" || { echo "Flex Consumption VNet integration subnet delegation is required." >&2; exit 1; }
grep -q "Microsoft.Network/privateEndpoints" "$BICEP_FILE" || { echo "Private endpoints must be part of the private networking baseline." >&2; exit 1; }
grep -q "Microsoft.Network/privateDnsZones" "$BICEP_FILE" || { echo "Private DNS zones must be part of the private networking baseline." >&2; exit 1; }
grep -q "virtualNetworkSubnetId" "$BICEP_FILE" || { echo "Function outbound VNet integration must be configured." >&2; exit 1; }
grep -q "diagnosticSettings" "$BICEP_FILE" || { echo "Function diagnostics must be configured." >&2; exit 1; }
grep -q "networkAclBypass: enablePrivateNetworking ? 'None' : 'AzureServices'" "$BICEP_FILE" || { echo "Cosmos must disable network ACL bypass when private networking is enabled." >&2; exit 1; }
grep -q "ipRules: enablePrivateNetworking ? \\[\\] :" "$BICEP_FILE" || { echo "Cosmos must not keep public IP rules when private networking is enabled." >&2; exit 1; }

if grep -q "Microsoft.ContainerRegistry" "$BICEP_FILE"; then
  echo "ACR must not be part of the MVP baseline." >&2
  exit 1
fi

grep -q "targetScope = 'subscription'" "$BOOTSTRAP_BICEP_FILE" || { echo "Bootstrap must deploy at subscription scope." >&2; exit 1; }
grep -q "Microsoft.Resources/resourceGroups" "$BOOTSTRAP_BICEP_FILE" || { echo "Bootstrap must create resource groups through Bicep." >&2; exit 1; }
grep -R -q "Microsoft.ManagedIdentity/userAssignedIdentities" "$ROOT_DIR/infrastructure/bootstrap" || { echo "Bootstrap must create the GitHub Actions managed identity." >&2; exit 1; }
grep -R -q "federatedIdentityCredentials" "$ROOT_DIR/infrastructure/bootstrap" || { echo "Bootstrap must configure GitHub OIDC federated credentials." >&2; exit 1; }
grep -R -q "repo:\${githubOrgSubject}/\${githubRepoSubject}:ref:\${githubRef}" "$ROOT_DIR/infrastructure/bootstrap" || { echo "Federated credential must use GitHub immutable OIDC subject format." >&2; exit 1; }
grep -R -q "Microsoft.Authorization/roleAssignments" "$ROOT_DIR/infrastructure/bootstrap" || { echo "Bootstrap must assign target resource group RBAC." >&2; exit 1; }

echo "Infrastructure guard tests passed."
