targetScope = 'resourceGroup'

@description('Deployment environment name.')
@allowed([
  'dev'
])
param environmentName string

@description('Azure region for Voxa private endpoints.')
param location string = resourceGroup().location

@description('Whether to deploy Cosmos DB private endpoint resources.')
param deployCosmos bool = false

@description('Whether to deploy private Function App ingress resources.')
param enablePrivateFunctionIngress bool = false

@description('Workload resource group containing the private link target resources.')
param workloadResourceGroupName string = 'rg-voxa-${environmentName}'

@description('Common Azure resource tags.')
param tags object = {
  application: 'voxa'
  environment: environmentName
  managedBy: 'bicep'
  costProfile: 'minimal'
  workloadBoundary: 'network'
}

var workloadResourceGroup = resourceGroup(workloadResourceGroupName)
var workloadResourceGroupId = subscriptionResourceId('Microsoft.Resources/resourceGroups', workloadResourceGroupName)
var resourceToken = uniqueString(subscription().id, workloadResourceGroupId, location, environmentName)
var privateEndpointToken = uniqueString(subscription().id, resourceGroup().name, workloadResourceGroupId, location, environmentName)
var keyVaultPrivateEndpointIpAddress = '10.42.0.40'
var storageQueuePrivateEndpointIpAddress = '10.42.0.41'
var storageBlobPrivateEndpointIpAddress = '10.42.0.42'
var storageTablePrivateEndpointIpAddress = '10.42.0.43'

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-03-01' existing = {
  name: 'azvnet${resourceToken}'
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-03-01' existing = {
  parent: virtualNetwork
  name: 'private-endpoints'
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  scope: workloadResourceGroup
  name: take('azstg${resourceToken}', 24)
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  scope: workloadResourceGroup
  name: take('azkv${resourceToken}', 24)
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' existing = if (enablePrivateFunctionIngress) {
  scope: workloadResourceGroup
  name: 'azfun${resourceToken}'
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = if (deployCosmos) {
  scope: workloadResourceGroup
  name: 'azcos${resourceToken}'
}

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.blob.core.windows.net'
}

resource queuePrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.queue.core.windows.net'
}

resource tablePrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.table.core.windows.net'
}

resource vaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.vaultcore.azure.net'
}

resource functionPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = if (enablePrivateFunctionIngress) {
  name: 'privatelink.azurewebsites.net'
}

resource cosmosPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = if (deployCosmos) {
  name: 'privatelink.documents.azure.com'
}

resource storageBlobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-03-01' = {
  name: 'azpepb${privateEndpointToken}'
  location: location
  tags: tags
  properties: {
    customNetworkInterfaceName: 'aznicpepb${privateEndpointToken}'
    subnet: {
      id: privateEndpointSubnet.id
    }
    ipConfigurations: [
      {
        name: 'blob'
        properties: {
          groupId: 'blob'
          memberName: 'blob'
          privateIPAddress: storageBlobPrivateEndpointIpAddress
        }
      }
    ]
    privateLinkServiceConnections: [
      {
        name: 'storage-blob'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource storageBlobPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-03-01' = {
  parent: storageBlobPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: blobPrivateDnsZone.id
        }
      }
    ]
  }
}

resource storageBlobPrivateDnsRecord 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: blobPrivateDnsZone
  name: storageAccount.name
  properties: {
    ttl: 10
    aRecords: [
      {
        ipv4Address: storageBlobPrivateEndpointIpAddress
      }
    ]
  }
}

resource storageQueuePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-03-01' = {
  name: 'azpepq${privateEndpointToken}'
  location: location
  tags: tags
  properties: {
    customNetworkInterfaceName: 'aznicpepq${privateEndpointToken}'
    subnet: {
      id: privateEndpointSubnet.id
    }
    ipConfigurations: [
      {
        name: 'queue'
        properties: {
          groupId: 'queue'
          memberName: 'queue'
          privateIPAddress: storageQueuePrivateEndpointIpAddress
        }
      }
    ]
    privateLinkServiceConnections: [
      {
        name: 'storage-queue'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'queue'
          ]
        }
      }
    ]
  }
}

resource storageQueuePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-03-01' = {
  parent: storageQueuePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'queue'
        properties: {
          privateDnsZoneId: queuePrivateDnsZone.id
        }
      }
    ]
  }
}

resource storageQueuePrivateDnsRecord 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: queuePrivateDnsZone
  name: storageAccount.name
  properties: {
    ttl: 10
    aRecords: [
      {
        ipv4Address: storageQueuePrivateEndpointIpAddress
      }
    ]
  }
}

resource storageTablePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-03-01' = {
  name: 'azpept${privateEndpointToken}'
  location: location
  tags: tags
  properties: {
    customNetworkInterfaceName: 'aznicpept${privateEndpointToken}'
    subnet: {
      id: privateEndpointSubnet.id
    }
    ipConfigurations: [
      {
        name: 'table'
        properties: {
          groupId: 'table'
          memberName: 'table'
          privateIPAddress: storageTablePrivateEndpointIpAddress
        }
      }
    ]
    privateLinkServiceConnections: [
      {
        name: 'storage-table'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'table'
          ]
        }
      }
    ]
  }
}

resource storageTablePrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-03-01' = {
  parent: storageTablePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'table'
        properties: {
          privateDnsZoneId: tablePrivateDnsZone.id
        }
      }
    ]
  }
}

resource storageTablePrivateDnsRecord 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: tablePrivateDnsZone
  name: storageAccount.name
  properties: {
    ttl: 10
    aRecords: [
      {
        ipv4Address: storageTablePrivateEndpointIpAddress
      }
    ]
  }
}

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-03-01' = {
  name: 'azpepk${privateEndpointToken}'
  location: location
  tags: tags
  properties: {
    customNetworkInterfaceName: 'aznicpepk${privateEndpointToken}'
    subnet: {
      id: privateEndpointSubnet.id
    }
    ipConfigurations: [
      {
        name: 'vault'
        properties: {
          groupId: 'vault'
          memberName: 'default'
          privateIPAddress: keyVaultPrivateEndpointIpAddress
        }
      }
    ]
    privateLinkServiceConnections: [
      {
        name: 'key-vault'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource keyVaultPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-03-01' = {
  parent: keyVaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vault'
        properties: {
          privateDnsZoneId: vaultPrivateDnsZone.id
        }
      }
    ]
  }
}

resource keyVaultPrivateDnsRecord 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: vaultPrivateDnsZone
  name: keyVault.name
  properties: {
    ttl: 10
    aRecords: [
      {
        ipv4Address: keyVaultPrivateEndpointIpAddress
      }
    ]
  }
}

resource functionPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-03-01' = if (enablePrivateFunctionIngress) {
  name: 'azpepf${privateEndpointToken}'
  location: location
  tags: tags
  properties: {
    customNetworkInterfaceName: 'aznicpepf${privateEndpointToken}'
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'function-app'
        properties: {
          privateLinkServiceId: functionApp.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }
}

resource functionPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-03-01' = if (enablePrivateFunctionIngress) {
  parent: functionPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'sites'
        properties: {
          privateDnsZoneId: functionPrivateDnsZone.id
        }
      }
    ]
  }
}

resource cosmosPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-03-01' = if (deployCosmos) {
  name: 'azpepc${privateEndpointToken}'
  location: location
  tags: tags
  properties: {
    customNetworkInterfaceName: 'aznicpepc${privateEndpointToken}'
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'cosmos-sql'
        properties: {
          privateLinkServiceId: cosmosAccount.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
}

resource cosmosPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-03-01' = if (deployCosmos) {
  parent: cosmosPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'documents'
        properties: {
          privateDnsZoneId: cosmosPrivateDnsZone.id
        }
      }
    ]
  }
}

output storageBlobPrivateEndpointName string = storageBlobPrivateEndpoint.name
output storageQueuePrivateEndpointName string = storageQueuePrivateEndpoint.name
output storageTablePrivateEndpointName string = storageTablePrivateEndpoint.name
output keyVaultPrivateEndpointName string = keyVaultPrivateEndpoint.name
output functionPrivateEndpointName string = enablePrivateFunctionIngress ? functionPrivateEndpoint.name : ''
output cosmosPrivateEndpointName string = deployCosmos ? cosmosPrivateEndpoint.name : ''
