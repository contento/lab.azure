# Typecast: Separate API

Typecast is a static Azure Static Web App with an independently deployed Node.js API on Azure Container Apps. The browser calls the API through a generated `config.js` endpoint; the API is not hosted by the Static Web Apps Functions runtime.

## Local development

```bash
./start-local.sh
```

```powershell
pwsh ./start-local.ps1
```

The scripts start the Node API on `http://localhost:7071` and use Static Web Apps CLI to serve the client at `http://localhost:4280`. Set `SWA_PORT` to run a second instance, for example `SWA_PORT=4281 ./start-local.sh` or `$env:SWA_PORT=4281; pwsh ./start-local.ps1`. Sessions are JSON files under `api/.sessions/`. Local runs use no Entra ID or Azure Storage.

## Deploy

The deployment helper builds the API image in Azure Container Registry, deploys it to Azure Container Apps, creates or updates the Static Web App, restricts API CORS to the web app origin, generates the deployed API URL for the client, and publishes the static client.

```bash
./deploy.sh rg-typecast-dev typecast-web-unique typecast-env typecast-api typecastregistry
```

```powershell
pwsh ./deploy.ps1 -ResourceGroupName rg-typecast-dev -StaticWebAppName typecast-web-unique -ContainerAppsEnvironmentName typecast-env -ApiName typecast-api -ContainerRegistryName typecastregistry
```

The deployment requires Azure CLI login, PowerShell 7+, Node.js 20 or 22 LTS, and globally unique names for the Static Web App and container registry. The current API persists sessions to its Container Apps local filesystem and is appropriate for development demonstrations; use durable external storage before running multiple replicas or depending on retained production history.
