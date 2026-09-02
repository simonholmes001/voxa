targetScope = 'resourceGroup'

@description('Deployment environment name.')
@allowed([
  'dev'
])
param environmentName string

@description('Azure region for Voxa resources.')
param location string = resourceGroup().location

@secure()
@description('OpenAI API key to store in Key Vault. Use a placeholder in validation environments if the app is not deployed yet.')
@minLength(1)
param openAiApiKey string

@secure()
@description('Signing key for Voxa app session access tokens.')
@minLength(32)
param appSessionSigningKey string

@description('Apple client identifier used as the expected audience for Sign in with Apple identity tokens.')
@minLength(1)
param appleClientId string

@description('Apple Developer Team ID used to validate authorization codes.')
@minLength(10)
param appleTeamId string

@description('Apple Sign in with Apple private key identifier.')
@minLength(10)
param appleKeyId string

@secure()
@description('Apple Sign in with Apple private key PEM used to create Apple client secrets.')
@minLength(32)
param applePrivateKey string

@description('Whether to deploy Cosmos DB serverless as the initial durable store candidate.')
param deployCosmos bool = false

@description('Deploy private networking controls: VNet integration, private endpoints, and private DNS zones.')
param enablePrivateNetworking bool = true

@description('Temporary dev/test escape hatch. Keep false for production.')
param allowPublicNetworkAccessForDev bool = false

@description('Make the Function App ingress private. Leave false for the mobile MVP unless a public edge such as Front Door, API Management, or VPN is added.')
param enablePrivateFunctionIngress bool = false

@description('Resource group that contains shared network resources for this environment.')
param networkResourceGroupName string = 'rg-voxa-network-${environmentName}'

@description('Application Insights daily data cap in GB.')
@minValue(1)
param appInsightsDailyCapGb int = 1

@description('Common Azure resource tags.')
param tags object = {
  application: 'voxa'
  environment: environmentName
  managedBy: 'bicep'
  costProfile: 'minimal'
}

var resourceToken = uniqueString(subscription().id, resourceGroup().id, location, environmentName)
var storageBlobDataOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
var storageBlobDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var storageQueueDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
var storageTableDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
var monitoringMetricsPublisherRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
var keyVaultSecretsOfficerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
var keyVaultSecretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var publicNetworkAccessValue = enablePrivateNetworking && !allowPublicNetworkAccessForDev ? 'Disabled' : 'Enabled'
var functionPublicNetworkAccessValue = enablePrivateFunctionIngress ? 'Disabled' : 'Enabled'
var networkResourceGroup = resourceGroup(networkResourceGroupName)

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-03-01' existing = if (enablePrivateNetworking) {
  scope: networkResourceGroup
  name: 'azvnet${resourceToken}'
}

resource functionIntegrationSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-03-01' existing = if (enablePrivateNetworking) {
  parent: virtualNetwork
  name: 'function-integration'
}

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'azidn${resourceToken}'
  location: location
  tags: tags
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: take('azstg${resourceToken}', 24)
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: publicNetworkAccessValue
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource deploymentStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: take('azdep${resourceToken}', 24)
  location: location
  tags: union(tags, {
    workloadBoundary: 'deployment-artifact'
  })
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

resource deploymentBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: deploymentStorageAccount
  name: 'default'
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: deploymentBlobService
  name: 'function-releases'
  properties: {
    publicAccess: 'None'
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource learnerStateTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'LearnerState'
}

resource refreshSessionsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'RefreshSessions'
}

resource realtimeSessionAuditTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'RealtimeSessionAudit'
}

resource realtimeSessionRateLimitTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'RealtimeSessionRateLimit'
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: take('azkv${resourceToken}', 24)
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    enabledForTemplateDeployment: false
    publicNetworkAccess: publicNetworkAccessValue
    softDeleteRetentionInDays: 7
  }
}

resource appKeyVaultSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, appIdentity.id, keyVaultSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsOfficerRoleId
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource appKeyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, appIdentity.id, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRoleId
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource openAiSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'openai-api-key'
  properties: {
    value: openAiApiKey
  }
  dependsOn: [
    appKeyVaultSecretsOfficer
  ]
}

resource appSessionSigningKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'app-session-signing-key'
  properties: {
    value: appSessionSigningKey
  }
  dependsOn: [
    appKeyVaultSecretsOfficer
  ]
}

resource applePrivateKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'apple-private-key'
  properties: {
    value: applePrivateKey
  }
  dependsOn: [
    appKeyVaultSecretsOfficer
  ]
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'azlog${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'azain${resourceToken}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    RetentionInDays: 30
    IngestionMode: 'LogAnalytics'
  }
}

resource appInsightsDailyCap 'Microsoft.Insights/components/CurrentBillingFeatures@2020-02-02' = {
  parent: appInsights
  name: 'current'
  properties: {
    DataVolumeCap: {
      Cap: appInsightsDailyCapGb
      StopSendNotificationWhenHitCap: false
      StopSendNotificationWhenHitThreshold: false
      WarningThreshold: 80
    }
  }
}

resource functionPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'azasp${resourceToken}'
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: 'azfun${resourceToken}'
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: functionPlan.id
    httpsOnly: true
    publicNetworkAccess: functionPublicNetworkAccessValue
    keyVaultReferenceIdentity: appIdentity.id
    virtualNetworkSubnetId: enablePrivateNetworking ? functionIntegrationSubnet.id : null
    functionAppConfig: {
      runtime: {
        name: 'dotnet-isolated'
        version: '10.0'
      }
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${deploymentStorageAccount.properties.primaryEndpoints.blob}${deploymentContainer.name}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: appIdentity.id
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 10
        instanceMemoryMB: 512
      }
    }
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccount.name
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: appIdentity.properties.clientId
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: appIdentity.properties.clientId
        }
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: enablePrivateNetworking ? '1' : '0'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'OPENAI_API_KEY'
          value: '@Microsoft.KeyVault(SecretUri=${openAiSecret.properties.secretUriWithVersion})'
        }
        {
          name: 'APP_SESSION_SIGNING_KEY'
          value: '@Microsoft.KeyVault(SecretUri=${appSessionSigningKeySecret.properties.secretUriWithVersion})'
        }
        {
          name: 'APPLE_CLIENT_ID'
          value: appleClientId
        }
        {
          name: 'APPLE_TEAM_ID'
          value: appleTeamId
        }
        {
          name: 'APPLE_KEY_ID'
          value: appleKeyId
        }
        {
          name: 'APPLE_PRIVATE_KEY'
          value: '@Microsoft.KeyVault(SecretUri=${applePrivateKeySecret.properties.secretUriWithVersion})'
        }
        {
          name: 'APPLE_TENANT_ID'
          value: 'tenant-default'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'VOXA_ENVIRONMENT'
          value: environmentName
        }
      ]
    }
  }
  dependsOn: [
    appKeyVaultSecretsUser
    appStorageBlobDataOwner
    appStorageBlobDataContributor
    appStorageQueueDataContributor
    appStorageTableDataContributor
    appDeploymentStorageBlobDataOwner
    appMonitoringMetricsPublisher
    learnerStateTable
    refreshSessionsTable
    realtimeSessionAuditTable
    realtimeSessionRateLimitTable
  ]
}

resource appStorageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, appIdentity.id, storageBlobDataOwnerRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataOwnerRoleId
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource appStorageBlobDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, appIdentity.id, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource appStorageQueueDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, appIdentity.id, storageQueueDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageQueueDataContributorRoleId
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource appStorageTableDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, appIdentity.id, storageTableDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: storageTableDataContributorRoleId
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource appDeploymentStorageBlobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(deploymentStorageAccount.id, appIdentity.id, storageBlobDataOwnerRoleId)
  scope: deploymentStorageAccount
  properties: {
    roleDefinitionId: storageBlobDataOwnerRoleId
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource appMonitoringMetricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, appIdentity.id, monitoringMetricsPublisherRoleId)
  properties: {
    roleDefinitionId: monitoringMetricsPublisherRoleId
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'function-logs'
  scope: functionApp
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = if (deployCosmos) {
  name: 'azcos${resourceToken}'
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    enableFreeTier: true
    enableAutomaticFailover: false
    publicNetworkAccess: publicNetworkAccessValue
    networkAclBypass: enablePrivateNetworking ? 'None' : 'AzureServices'
    ipRules: enablePrivateNetworking ? [] : [
      {
        ipAddressOrRange: '0.0.0.0'
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = if (deployCosmos) {
  parent: cosmosAccount
  name: 'voxa'
  properties: {
    resource: {
      id: 'voxa'
    }
  }
}

resource learnerContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = if (deployCosmos) {
  parent: cosmosDatabase
  name: 'learner-events'
  properties: {
    resource: {
      id: 'learner-events'
      partitionKey: {
        paths: [
          '/userId'
        ]
        kind: 'Hash'
      }
    }
  }
}

output functionAppName string = functionApp.name
output functionAppHostName string = functionApp.properties.defaultHostName
output functionAppManagedIdentityResourceId string = appIdentity.id
output keyVaultName string = keyVault.name
output storageAccountName string = storageAccount.name
output deploymentStorageAccountName string = deploymentStorageAccount.name
output learnerStateTableName string = learnerStateTable.name
output refreshSessionsTableName string = refreshSessionsTable.name
output realtimeSessionAuditTableName string = realtimeSessionAuditTable.name
output realtimeSessionRateLimitTableName string = realtimeSessionRateLimitTable.name
output applicationInsightsName string = appInsights.name
output cosmosAccountName string = deployCosmos ? cosmosAccount.name : ''
output virtualNetworkName string = enablePrivateNetworking ? virtualNetwork.name : ''
