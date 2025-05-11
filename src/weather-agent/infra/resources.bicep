@description('The location used for all deployed resources')
param location string = resourceGroup().location

@description('Tags that will be applied to all resources')
param tags object = {}

param weatherAgentExists bool

@description('Id of the user or app to assign application roles')
param principalId string

@description('client secret')
@secure()
param clientSecret string

@description('Azure OpenAI API key')
@secure()
param azureOpenAIAPIKey string

@description('The port the container will listen on')
param targetPort string

@description('The name of the Azure subscription')

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = uniqueString(subscription().id, resourceGroup().id, location)

// Monitor application with Azure Monitor
module monitoring 'br/public:avm/ptn/azd/monitoring:0.1.0' = {
  name: 'monitoring'
  params: {
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}${resourceToken}'
    applicationInsightsDashboardName: '${abbrs.portalDashboards}${resourceToken}'
    location: location
    tags: tags
  }
}
// Container registry
module containerRegistry 'br/public:avm/res/container-registry/registry:0.1.1' = {
  name: 'registry'
  params: {
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    tags: tags
    publicNetworkAccess: 'Enabled'
    roleAssignments:[
      {
        principalId: weatherAgentIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
      }
    ]
  }
}

// Container apps environment
module containerAppsEnvironment 'br/public:avm/res/app/managed-environment:0.4.5' = {
  name: 'container-apps-environment'
  params: {
    logAnalyticsWorkspaceResourceId: monitoring.outputs.logAnalyticsWorkspaceResourceId
    name: '${abbrs.appManagedEnvironments}${resourceToken}'
    location: location
    zoneRedundant: false
  }
}

module weatherAgentIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.2.1' = {
  name: 'weatherAgentidentity'
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}weatherAgent-${resourceToken}'
    location: location
  }
}
module weatherAgentFetchLatestImage './modules/fetch-container-image.bicep' = {
  name: 'weatherAgent-fetch-image'
  params: {
    exists: weatherAgentExists
    name: 'weatherAgent'
  }
}

module weatherAgent 'br/public:avm/res/app/container-app:0.8.0' = {
  name: 'weatherAgent'
  params: {
    name: 'weatheragent'
    ingressTargetPort: int(targetPort)
    scaleMinReplicas: 1
    scaleMaxReplicas: 10
    secrets: {
      secureList:  [
        {
          name: 'clientsecret'
          value: clientSecret
        }
        {
          name: 'azureopenaiapikey'
          value: azureOpenAIAPIKey
        }
      ]
    }
    containers: [
      {
        image: weatherAgentFetchLatestImage.outputs.?containers[?0].?image ?? 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
        name: 'main'
        resources: {
          cpu: json('0.5')
          memory: '1.0Gi'
        }
        env: [
          {
            name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
            value: monitoring.outputs.applicationInsightsConnectionString
          }
          {
            name: 'AZURE_CLIENT_ID'
            value: weatherAgentIdentity.outputs.clientId
          }
          {
            name: 'TARGET_PORT'
            value: targetPort
          }
          {
            name: 'CLIENT_SECRET'
            secretRef: 'clientsecret'
          }
          {
            name: 'AZURE_OPENAI_API_KEY'
            secretRef: 'azureopenaiapikey'
          }
          {
            name: 'ASPNETCORE_ENVIRONMENT'
            value: 'Production'
          }
        ]
      }
    ]
    managedIdentities:{
      systemAssigned: false
      userAssignedResourceIds: [weatherAgentIdentity.outputs.resourceId]
    }
    registries:[
      {
        server: containerRegistry.outputs.loginServer
        identity: weatherAgentIdentity.outputs.resourceId
      }
    ]
    environmentResourceId: containerAppsEnvironment.outputs.resourceId
    location: location
    tags: union(tags, { 'azd-service-name': 'weatherAgent' })
  }
}
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer
output AZURE_RESOURCE_AGENT_ID string = weatherAgent.outputs.resourceId
