#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BICEP_FILE="$ROOT_DIR/infrastructure/bicep/main.bicep"
NETWORK_BICEP_FILE="$ROOT_DIR/infrastructure/bicep/network.bicep"
PRIVATE_ENDPOINTS_BICEP_FILE="$ROOT_DIR/infrastructure/bicep/private-endpoints.bicep"
BOOTSTRAP_BICEP_FILE="$ROOT_DIR/infrastructure/bootstrap/main.bicep"
DEPLOY_WORKFLOW_FILE="$ROOT_DIR/.github/workflows/infrastructure-deploy-dev.yaml"

[ -f "$BICEP_FILE" ] || { echo "Missing $BICEP_FILE" >&2; exit 1; }
[ -f "$NETWORK_BICEP_FILE" ] || { echo "Missing $NETWORK_BICEP_FILE" >&2; exit 1; }
[ -f "$PRIVATE_ENDPOINTS_BICEP_FILE" ] || { echo "Missing $PRIVATE_ENDPOINTS_BICEP_FILE" >&2; exit 1; }
[ -f "$BOOTSTRAP_BICEP_FILE" ] || { echo "Missing $BOOTSTRAP_BICEP_FILE" >&2; exit 1; }
[ -f "$DEPLOY_WORKFLOW_FILE" ] || { echo "Missing $DEPLOY_WORKFLOW_FILE" >&2; exit 1; }

grep -q "FlexConsumption" "$BICEP_FILE" || { echo "Function plan must use Flex Consumption." >&2; exit 1; }
grep -q "UserAssigned" "$BICEP_FILE" || { echo "Function app must use user-assigned managed identity." >&2; exit 1; }
grep -q "allowSharedKeyAccess: false" "$BICEP_FILE" || { echo "Storage local auth must be disabled." >&2; exit 1; }
grep -q "allowBlobPublicAccess: false" "$BICEP_FILE" || { echo "Storage blob public access must be disabled." >&2; exit 1; }
grep -q "resource deploymentStorageAccount" "$BICEP_FILE" || { echo "Function deployment packages must use dedicated deployment artifact storage." >&2; exit 1; }
grep -q "name: take('azdep\${resourceToken}', 24)" "$BICEP_FILE" || { echo "Deployment artifact storage naming must be deterministic and separate from runtime storage." >&2; exit 1; }
grep -q "publicNetworkAccess: 'Enabled'" "$BICEP_FILE" || { echo "Deployment artifact storage must be reachable by GitHub-hosted deployment tooling." >&2; exit 1; }
grep -q "value: '\${deploymentStorageAccount.properties.primaryEndpoints.blob}\${deploymentContainer.name}'" "$BICEP_FILE" || { echo "Function deployment storage must point at deployment artifact storage, not private runtime storage." >&2; exit 1; }
grep -q "AzureWebJobsStorage__accountName" "$BICEP_FILE" || { echo "Function runtime storage account setting must be present." >&2; exit 1; }
grep -q "value: storageAccount.name" "$BICEP_FILE" || { echo "Function runtime storage must remain on the private runtime storage account." >&2; exit 1; }
grep -q "enableRbacAuthorization: true" "$BICEP_FILE" || { echo "Key Vault must use RBAC authorization." >&2; exit 1; }
grep -q "param enablePrivateNetworking bool = true" "$BICEP_FILE" || { echo "Private networking must be enabled by default." >&2; exit 1; }
grep -q "param allowPublicNetworkAccessForDev bool = false" "$BICEP_FILE" || { echo "Public network access escape hatch must default to false." >&2; exit 1; }
grep -q "param enablePrivateFunctionIngress bool = false" "$BICEP_FILE" || { echo "Function private ingress must be an explicit opt-in for the mobile MVP." >&2; exit 1; }
grep -q "publicNetworkAccess: publicNetworkAccessValue" "$BICEP_FILE" || { echo "Data resources must use the private-network public access guard." >&2; exit 1; }
grep -q "publicNetworkAccess: functionPublicNetworkAccessValue" "$BICEP_FILE" || { echo "Function ingress must use an explicit public/private access guard." >&2; exit 1; }
grep -q "param networkResourceGroupName string = 'rg-voxa-network-\${environmentName}'" "$BICEP_FILE" || { echo "Workload deployment must reference the network resource group." >&2; exit 1; }
grep -q "var resourceToken = uniqueString(subscription().id, resourceGroup().id, location, environmentName)" "$BICEP_FILE" || { echo "Workload resource names must keep the original resource token seed." >&2; exit 1; }
if grep -q "Microsoft.Network/privateEndpoints" "$BICEP_FILE"; then
  echo "Private endpoints must not be deployed from the workload resource group template." >&2
  exit 1
fi
grep -q "var resourceToken = uniqueString(subscription().id, workloadResourceGroupId, location, environmentName)" "$NETWORK_BICEP_FILE" || { echo "Network resource names must use the original workload resource group seed." >&2; exit 1; }
grep -q "Microsoft.Network/virtualNetworks" "$NETWORK_BICEP_FILE" || { echo "A VNet must be part of the private networking baseline." >&2; exit 1; }
grep -q "Microsoft.App/environments" "$NETWORK_BICEP_FILE" || { echo "Flex Consumption VNet integration subnet delegation is required." >&2; exit 1; }
grep -q "Microsoft.Network/privateDnsZones" "$NETWORK_BICEP_FILE" || { echo "Private DNS zones must be part of the private networking baseline." >&2; exit 1; }
grep -q "targetScope = 'resourceGroup'" "$PRIVATE_ENDPOINTS_BICEP_FILE" || { echo "Private endpoints must deploy at network resource group scope." >&2; exit 1; }
grep -q "workloadResourceGroupName" "$PRIVATE_ENDPOINTS_BICEP_FILE" || { echo "Private endpoints must reference workload private link targets across the resource group boundary." >&2; exit 1; }
grep -q "var privateEndpointToken = uniqueString(subscription().id, resourceGroup().name, workloadResourceGroupId, location, environmentName)" "$PRIVATE_ENDPOINTS_BICEP_FILE" || { echo "Private endpoints must use a network-resource-group naming token." >&2; exit 1; }
grep -q "Microsoft.Network/privateEndpoints" "$PRIVATE_ENDPOINTS_BICEP_FILE" || { echo "Private endpoints must be deployed from the network resource group template." >&2; exit 1; }
grep -q "customNetworkInterfaceName" "$PRIVATE_ENDPOINTS_BICEP_FILE" || { echo "Private endpoint NIC names must be explicitly controlled." >&2; exit 1; }
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
grep -q "networkResourceGroupName" "$BOOTSTRAP_BICEP_FILE" || { echo "Bootstrap must create a separate network resource group." >&2; exit 1; }
grep -q "module networkResourceGroupContributor" "$BOOTSTRAP_BICEP_FILE" || { echo "Bootstrap must grant Contributor on the network resource group for ARM deployment operations." >&2; exit 1; }
grep -q "privateDnsZoneContributorRoleDefinitionId" "$BOOTSTRAP_BICEP_FILE" || { echo "Bootstrap must grant Private DNS Zone Contributor on the network resource group." >&2; exit 1; }
grep -q "roleBasedAccessControlAdministratorRoleDefinitionId" "$BOOTSTRAP_BICEP_FILE" || { echo "Bootstrap must grant workload-scoped RBAC Administrator for workload role assignments." >&2; exit 1; }
grep -R -q "Microsoft.ManagedIdentity/userAssignedIdentities" "$ROOT_DIR/infrastructure/bootstrap" || { echo "Bootstrap must create the GitHub Actions managed identity." >&2; exit 1; }
grep -R -q "federatedIdentityCredentials" "$ROOT_DIR/infrastructure/bootstrap" || { echo "Bootstrap must configure GitHub OIDC federated credentials." >&2; exit 1; }
grep -R -q "param federatedCredentialName string" "$ROOT_DIR/infrastructure/bootstrap" || { echo "Bootstrap must allow separate OIDC credential names for branch validation." >&2; exit 1; }
grep -R -q "repo:\${githubOrgSubject}/\${githubRepoSubject}:ref:\${githubRef}" "$ROOT_DIR/infrastructure/bootstrap" || { echo "Federated credential must use GitHub immutable OIDC subject format." >&2; exit 1; }
grep -R -q "Microsoft.Authorization/roleAssignments" "$ROOT_DIR/infrastructure/bootstrap" || { echo "Bootstrap must assign target resource group RBAC." >&2; exit 1; }
grep -q "bash ./infrastructure/scripts/deploy.sh dev" "$DEPLOY_WORKFLOW_FILE" || { echo "Deploy workflow must use the shared deploy script." >&2; exit 1; }
if grep -q "az deployment group create" "$DEPLOY_WORKFLOW_FILE"; then
  echo "Deploy workflow must not duplicate inline az deployment group create commands." >&2
  exit 1
fi
dotnet_setup_line="$(grep -n "uses: actions/setup-dotnet@v5" "$DEPLOY_WORKFLOW_FILE" | head -n 1 | cut -d: -f1)"
deploy_script_line="$(grep -n "run: bash ./infrastructure/scripts/deploy.sh dev" "$DEPLOY_WORKFLOW_FILE" | head -n 1 | cut -d: -f1)"
if [ -z "$dotnet_setup_line" ] || [ -z "$deploy_script_line" ] || [ "$dotnet_setup_line" -ge "$deploy_script_line" ]; then
  echo "Deploy workflow must install .NET before running the shared deploy script." >&2
  exit 1
fi

echo "Infrastructure guard tests passed."
