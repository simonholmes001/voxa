targetScope = 'resourceGroup'

@description('Deployment environment name.')
@allowed([
  'dev'
])
param environmentName string

@description('Azure region for Voxa network resources.')
param location string = resourceGroup().location

@description('Whether to include Cosmos DB private DNS for this environment.')
param deployCosmos bool = false

@description('Whether to include private Function App ingress DNS for this environment.')
param enablePrivateFunctionIngress bool = false

@description('Workload resource group name used to preserve stable cross-resource names.')
param workloadResourceGroupName string = 'rg-voxa-${environmentName}'

@description('Common Azure resource tags.')
param tags object = {
  application: 'voxa'
  environment: environmentName
  managedBy: 'bicep'
  costProfile: 'minimal'
  workloadBoundary: 'network'
}

var workloadResourceGroupId = subscriptionResourceId('Microsoft.Resources/resourceGroups', workloadResourceGroupName)
var resourceToken = uniqueString(subscription().id, workloadResourceGroupId, location, environmentName)

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-03-01' = {
  name: 'azvnet${resourceToken}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.42.0.0/24'
      ]
    }
    subnets: [
      {
        name: 'function-integration'
        properties: {
          addressPrefix: '10.42.0.0/27'
          delegations: [
            {
              name: 'function-flex-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: '10.42.0.32/27'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
  tags: tags
}

resource queuePrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.queue.core.windows.net'
  location: 'global'
  tags: tags
}

resource tablePrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  #disable-next-line no-hardcoded-env-urls
  name: 'privatelink.table.core.windows.net'
  location: 'global'
  tags: tags
}

resource vaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

resource functionPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = if (enablePrivateFunctionIngress) {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
  tags: tags
}

resource cosmosPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = if (deployCosmos) {
  name: 'privatelink.documents.azure.com'
  location: 'global'
  tags: tags
}

resource blobPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: blobPrivateDnsZone
  name: 'voxa-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource queuePrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: queuePrivateDnsZone
  name: 'voxa-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource tablePrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: tablePrivateDnsZone
  name: 'voxa-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource vaultPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: vaultPrivateDnsZone
  name: 'voxa-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource functionPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (enablePrivateFunctionIngress) {
  parent: functionPrivateDnsZone
  name: 'voxa-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource cosmosPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (deployCosmos) {
  parent: cosmosPrivateDnsZone
  name: 'voxa-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

output virtualNetworkName string = virtualNetwork.name
output functionIntegrationSubnetName string = 'function-integration'
output privateEndpointSubnetName string = 'private-endpoints'
