targetScope = 'resourceGroup'

@description('Principal object ID receiving deployment permissions.')
param principalId string

@description('Principal type receiving deployment permissions.')
@allowed([
  'ServicePrincipal'
])
param principalType string = 'ServicePrincipal'

@description('Fully qualified Azure role definition ID.')
param roleDefinitionId string

@description('Stable seed for the deterministic role assignment name.')
param roleAssignmentSeed string

resource deploymentRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, roleAssignmentSeed, roleDefinitionId)
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: principalType
  }
}

output roleAssignmentId string = deploymentRole.id
