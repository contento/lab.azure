@description('Lowercase application base name used for resource names.')
@minLength(2)
@maxLength(10)
param baseName string

@description('Deployment environment used for resource names.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string

@description('Azure region for the resources.')
param location string = resourceGroup().location

@description('Lowercase region code used for resource names.')
@minLength(2)
@maxLength(4)
param locationCode string

@description('Subscription ID used to derive globally unique resource-name suffixes.')
param subscriptionId string

@description('Tags applied to deployed resources.')
param tags object = {}

var uniqueSuffix = substring(replace(subscriptionId, '-', ''), 0, 8)
var namePrefix = '${baseName}-${environment}-${locationCode}'
var compactName = '${baseName}${environment}'
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
