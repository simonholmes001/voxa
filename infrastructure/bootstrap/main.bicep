targetScope = 'subscription'

@description('Deployment environment name.')
@allowed([
  'dev'
])
param environmentName string = 'dev'

@description('Azure region for bootstrap and target resource groups.')
param location string = deployment().location

@description('GitHub organization or user that owns the repository.')
param githubOrg string = 'simonholmes001'

@description('Immutable GitHub organization/user ID used in OIDC subject claims.')
param githubOrgId string = '31061938'

@description('GitHub repository name.')
param githubRepo string = 'voxa'

@description('Immutable GitHub repository ID used in OIDC subject claims.')
param githubRepoId string = '1347555953'

@description('GitHub ref allowed to deploy Azure resources.')
param githubRef string = 'refs/heads/main'

@description('Resource group that contains CI/CD identity resources.')
param pipelineResourceGroupName string = 'rg-voxa-pipeline-identity'

@description('Resource group that contains Voxa workload resources for this environment.')
param targetResourceGroupName string = 'rg-voxa-${environmentName}'

@description('Resource group that contains shared Voxa network resources for this environment.')
param networkResourceGroupName string = 'rg-voxa-network-${environmentName}'

@description('User-assigned managed identity used by GitHub Actions OIDC.')
param pipelineIdentityName string = 'id-voxa-github-actions'

@description('Azure role granted to the pipeline identity on the target resource group.')
@allowed([
  'Contributor'
])
param targetResourceGroupRole string = 'Contributor'

var contributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
var roleBasedAccessControlAdministratorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f58310d9-a9f6-439a-9e8d-f62e7b41a168')
var networkContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7')
var privateDnsZoneContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b12aa53e-6015-4669-85d0-8515ebb3ae7f')
var roleDefinitionIdByName = {
  Contributor: contributorRoleDefinitionId
}

resource pipelineResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: pipelineResourceGroupName
  location: location
  tags: {
    application: 'voxa'
    purpose: 'pipeline-identity'
    managedBy: 'bicep'
  }
}

resource targetResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: targetResourceGroupName
  location: location
  tags: {
    application: 'voxa'
    environment: environmentName
    managedBy: 'bicep'
    costProfile: 'minimal'
  }
}

resource networkResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: networkResourceGroupName
  location: location
  tags: {
    application: 'voxa'
    environment: environmentName
    managedBy: 'bicep'
    costProfile: 'minimal'
    workloadBoundary: 'network'
  }
}

module pipelineIdentity './modules/pipeline-identity.bicep' = {
  name: 'pipeline-identity-${environmentName}'
  scope: pipelineResourceGroup
  params: {
    location: location
    pipelineIdentityName: pipelineIdentityName
    githubOrg: githubOrg
    githubOrgId: githubOrgId
    githubRepo: githubRepo
    githubRepoId: githubRepoId
    githubRef: githubRef
  }
}

module targetResourceGroupRbac './modules/target-rbac.bicep' = {
  name: 'target-contributor-${environmentName}'
  scope: targetResourceGroup
  params: {
    principalId: pipelineIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitionIdByName[targetResourceGroupRole]
    roleAssignmentSeed: pipelineIdentity.outputs.identityId
  }
}

module targetResourceGroupRbacAdministrator './modules/target-rbac.bicep' = {
  name: 'target-rbac-admin-${environmentName}'
  scope: targetResourceGroup
  params: {
    principalId: pipelineIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleBasedAccessControlAdministratorRoleDefinitionId
    roleAssignmentSeed: '${pipelineIdentity.outputs.identityId}-rbac-admin'
  }
}

module networkResourceGroupNetworkContributor './modules/target-rbac.bicep' = {
  name: 'network-network-contributor-${environmentName}'
  scope: networkResourceGroup
  params: {
    principalId: pipelineIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: networkContributorRoleDefinitionId
    roleAssignmentSeed: pipelineIdentity.outputs.identityId
  }
}

module networkResourceGroupPrivateDnsContributor './modules/target-rbac.bicep' = {
  name: 'network-private-dns-contributor-${environmentName}'
  scope: networkResourceGroup
  params: {
    principalId: pipelineIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: privateDnsZoneContributorRoleDefinitionId
    roleAssignmentSeed: '${pipelineIdentity.outputs.identityId}-private-dns'
  }
}

output azureClientId string = pipelineIdentity.outputs.clientId
output azureTenantId string = tenant().tenantId
output azureSubscriptionId string = subscription().subscriptionId
output azureLocation string = location
output azureResourceGroup string = targetResourceGroup.name
output azureNetworkResourceGroup string = networkResourceGroup.name
output pipelineIdentityResourceGroup string = pipelineResourceGroup.name
output pipelineIdentityName string = pipelineIdentity.outputs.identityName
output federatedCredentialSubject string = pipelineIdentity.outputs.federatedCredentialSubject
