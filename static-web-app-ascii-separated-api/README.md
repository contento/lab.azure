# Typecast: Separate API

Typecast is a static Azure Static Web App with an independently deployed Node.js API on Azure Container Apps. The browser calls the API through a generated `config.js` endpoint; the API is not hosted by the Static Web Apps Functions runtime.

## Local development

```bash
./start-local.sh
```

```powershell
pwsh ./start-local.ps1
```

The scripts start the Node API on `http://127.0.0.1:7072` and use Static Web Apps CLI to serve the client at `http://localhost:4281`, avoiding the original sample's `7071` and `4280` defaults. Set `API_PORT` and `SWA_PORT` to override them, for example `API_PORT=7082 SWA_PORT=4282 ./start-local.sh` or `$env:API_PORT=7082; $env:SWA_PORT=4282; pwsh ./start-local.ps1`. Sessions are JSON files under `api/.sessions/`. Local runs use no Entra ID or Azure Storage.

## Deploy

The deployment helper builds the API image in Azure Container Registry, deploys it to Azure Container Apps, creates or updates the Static Web App, restricts API CORS to the web app origin, generates the deployed API URL for the client, and publishes the static client.

```bash
./deploy.sh typecast
```

```powershell
pwsh ./deploy.ps1 -BaseName typecast
```

The default deployment names are `rg-typecast-dev-eus`, `stapp-typecast-dev-eus-<subscription-suffix>`, `cae-typecast-dev-eus`, `ca-typecast-dev-eus-api`, `acrtypecastdev<subscription-suffix>`, and `log-typecast-dev-eus`. Use optional environment, Azure region, region code, and subscription ID arguments to override the defaults. The deployment requires Azure CLI login, PowerShell 7+, Node.js 20 or 22 LTS. The current API persists sessions to its Container Apps local filesystem and is appropriate for development demonstrations; use durable external storage before running multiple replicas or depending on retained production history.
