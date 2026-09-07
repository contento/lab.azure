@description('Azure region for the resources.')
param location string = resourceGroup().location

@description('Lowercase application, environment, and region prefix used for resource names.')
param namePrefix string

@description('Lowercase application and environment prefix used in Storage account names.')
@minLength(5)
param compactName string

@description('Subscription-derived suffix used for globally unique resource names.')
@minLength(8)
param uniqueSuffix string

@description('Tags applied to deployed resources.')
param tags object = {}

var sessionsContainerName = 'sessions'
var storageBlobDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var storageAccountName = 'st${compactName}${uniqueSuffix}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: { deleteRetentionPolicy: { enabled: true, days: 7 } }
}

resource sessionsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: sessionsContainerName
  properties: { publicAccess: 'None' }
}

resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: 'stapp-${namePrefix}-${uniqueSuffix}'
  location: location
  tags: tags
  sku: { name: 'Standard', tier: 'Standard' }
  identity: { type: 'SystemAssigned' }
  properties: { stagingEnvironmentPolicy: 'Enabled' }
}

resource storageAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, staticWebApp.id, storageBlobDataContributorRoleId)
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: staticWebApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output staticWebAppHostname string = staticWebApp.properties.defaultHostname
output staticWebAppResourceId string = staticWebApp.id
output storageAccountOutputName string = storageAccount.name
output sessionsContainerOutputName string = sessionsContainer.name
