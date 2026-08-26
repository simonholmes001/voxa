targetScope = 'subscription'

@description('Deployment environment name.')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environmentName string = 'dev'

@description('Azure region for bootstrap and target resource groups.')
param location string = deployment().location

@description('GitHub organization or user that owns the repository.')
param githubOrg string = 'simonholmes001'

@description('GitHub repository name.')
param githubRepo string = 'voxa'

@description('GitHub environment name used by Azure deployment workflows.')
param githubEnvironment string = environmentName

@description('Resource group that contains CI/CD identity resources.')
param pipelineResourceGroupName string = 'rg-voxa-pipeline-identity'

@description('Resource group that contains Voxa workload resources for this environment.')
param targetResourceGroupName string = 'rg-voxa-${environmentName}'

@description('User-assigned managed identity used by GitHub Actions OIDC.')
param pipelineIdentityName string = 'id-voxa-github-actions'

@description('Azure role granted to the pipeline identity on the target resource group.')
@allowed([
  'Contributor'
])
param targetResourceGroupRole string = 'Contributor'

var contributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
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

module pipelineIdentity './modules/pipeline-identity.bicep' = {
  name: 'pipeline-identity-${environmentName}'
  scope: pipelineResourceGroup
  params: {
    location: location
    pipelineIdentityName: pipelineIdentityName
    githubOrg: githubOrg
    githubRepo: githubRepo
    githubEnvironment: githubEnvironment
  }
}

module targetResourceGroupRbac './modules/target-rbac.bicep' = {
  name: 'target-rbac-${environmentName}'
  scope: targetResourceGroup
  params: {
    principalId: pipelineIdentity.outputs.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitionIdByName[targetResourceGroupRole]
    roleAssignmentSeed: pipelineIdentity.outputs.identityId
  }
}

output azureClientId string = pipelineIdentity.outputs.clientId
output azureTenantId string = tenant().tenantId
output azureSubscriptionId string = subscription().subscriptionId
output azureLocation string = location
output azureResourceGroup string = targetResourceGroup.name
output pipelineIdentityResourceGroup string = pipelineResourceGroup.name
output pipelineIdentityName string = pipelineIdentity.outputs.identityName
output federatedCredentialSubject string = pipelineIdentity.outputs.federatedCredentialSubject
