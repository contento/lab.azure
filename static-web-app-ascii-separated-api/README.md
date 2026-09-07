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

The checked-in `infra/parameters.dev.bicepparam` supplies the default base name (`asciitype`), environment (`dev`), location (`eastus2`), region code (`eus2`), and active development subscription. Copy `infra/parameters.template.bicepparam` for a future subscription or environment.

### 1. Code deployment (`app/` and `api/`)
Builds and updates the API image in Azure Container Apps, generates client endpoint configuration, and publishes the static client:

```bash
./deploy-code.sh
```

```powershell
pwsh ./deploy-code.ps1
```

### 2. Infrastructure deployment
Provision or update Azure Resource Groups, Container Registries, Container Apps Environments, Container Apps, Log Analytics, and Static Web Apps:

```bash
./infra/deploy-infrastructure.sh
```

```powershell
pwsh ./infra/deploy-infrastructure.ps1
```

The default deployment names are `rg-asciitype-dev-eus2`, `stapp-asciitype-dev-eus2-<subscription-suffix>`, `cae-asciitype-dev-eus2`, `ca-asciitype-dev-eus2-api`, `acrasciitypedev<subscription-suffix>`, and `log-asciitype-dev-eus2`. Both helpers accept optional positional shell arguments or PowerShell parameters to override the base name, environment, Azure region, region code, and subscription ID.
