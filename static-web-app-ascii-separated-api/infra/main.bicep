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

@description('Container image, including registry path and tag.')
param apiImage string

@description('Container registry server hosting the API image.')
param registryServer string

@description('Container registry administrator username.')
param registryUsername string

@secure()
@description('Container registry administrator password.')
param registryPassword string

@description('The Static Web App hostname allowed to call the API.')
param allowedOrigin string

var uniqueSuffix = substring(replace(subscriptionId, '-', ''), 0, 8)
var namePrefix = '${baseName}-${environment}-${locationCode}'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${namePrefix}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${namePrefix}'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

resource api 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-${namePrefix}-api'
  location: location
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      registries: [
        {
          server: registryServer
          username: registryUsername
          passwordSecretRef: 'registry-password'
        }
      ]
      secrets: [
        {
          name: 'registry-password'
          value: registryPassword
        }
      ]
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        corsPolicy: {
          allowedOrigins: [ allowedOrigin ]
          allowedMethods: [ 'GET', 'POST', 'DELETE', 'OPTIONS' ]
          allowedHeaders: [ 'content-type' ]
        }
      }
    }
    template: {
      containers: [
        {
          name: 'api'
          image: apiImage
          env: [
            { name: 'PORT', value: '8080' }
            { name: 'ALLOWED_ORIGIN', value: allowedOrigin }
          ]
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: 'stapp-${namePrefix}-${uniqueSuffix}'
  location: location
  sku: { name: 'Standard', tier: 'Standard' }
  // ARM preflight validation requires an explicit (even empty) properties object for this API version.
  properties: {}
}

output endpoints object = {
  api: 'https://${api.properties.configuration.ingress.fqdn}'
  web: 'https://${staticWebApp.properties.defaultHostname}'
}
