targetScope = 'resourceGroup'

@description('Azure region for the managed identity.')
param location string

@description('User-assigned managed identity used by GitHub Actions OIDC.')
param pipelineIdentityName string

@description('GitHub organization or user that owns the repository.')
param githubOrg string

@description('GitHub repository name.')
param githubRepo string

@description('GitHub environment name used by Azure deployment workflows.')
param githubEnvironment string

var federatedCredentialName = 'github-${githubEnvironment}'

resource pipelineIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: pipelineIdentityName
  location: location
  tags: {
    application: 'voxa'
    purpose: 'github-actions'
    managedBy: 'bicep'
  }
}

resource githubFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: pipelineIdentity
  name: federatedCredentialName
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubOrg}/${githubRepo}:environment:${githubEnvironment}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

output clientId string = pipelineIdentity.properties.clientId
output principalId string = pipelineIdentity.properties.principalId
output identityId string = pipelineIdentity.id
output identityName string = pipelineIdentity.name
output federatedCredentialSubject string = githubFederatedCredential.properties.subject
