# Typecast Separate API Agent Guide

## Scope

This directory is an independent Typecast sample. Keep changes inside this module unless the task explicitly requires workspace-wide updates. Do not alter `static-web-app-ascii/` or `keyvault/` while working here.

## Architecture

- `app/`: plain static HTML, CSS, and JavaScript deployed to Azure Static Web Apps. It reads the API origin from generated `config.js`.
- `api/`: standalone ESM Node.js HTTP service, deployed separately to Azure Container Apps. It owns ASCII rendering, request validation, CORS headers, and session persistence.
- `infra/`: Bicep resources for Azure Container Apps, Container Registry, Log Analytics, and Static Web Apps.
- `start-local.*`: run the API and static client as separate local processes.
- `deploy.*`: build the API container in ACR, provision or update infrastructure, generate the frontend API configuration, and publish the static client.

## Security Rules

- Do not put API implementation details, credentials, or storage access in `app/`.
- Treat all browser input as untrusted and validate it in `api/` before rendering or persisting it.
- Keep `api/.env`, `api/.sessions/`, and `app/config.js` out of source control.
- Preserve the exact allowed frontend origin in both Container Apps ingress CORS configuration and the API's `ALLOWED_ORIGIN` setting.
- Do not log, commit, or print deployment tokens, ACR credentials, or generated configuration containing secrets.
- The current API is intentionally unauthenticated and uses ephemeral local storage. Do not describe it as user-isolated or production-ready until authentication and durable storage are implemented.

## Commands

From `api/` after installing dependencies:

```text
npm test
npm run lint
```

From this module root:

```text
./start-local.sh
pwsh ./start-local.ps1
./deploy-code.sh [base-name] [environment] [location] [location-code] [subscription-id]
pwsh ./deploy-code.ps1 [-BaseName <name>] [-Environment dev|test|prod] [-Location <azure-region>] [-LocationCode <region-code>] [-SubscriptionId <subscription-id>]
./infra/deploy-infrastructure.sh [base-name] [environment] [location] [location-code] [subscription-id]
pwsh ./infra/deploy-infrastructure.ps1 [-BaseName <name>] [-Environment dev|test|prod] [-Location <azure-region>] [-LocationCode <region-code>] [-SubscriptionId <subscription-id>]
pwsh ./add-user.ps1 [-User <email-or-upn>] [-Role admin|user] [-BaseName <name>] [-Environment dev|test|prod] [-LocationCode <region-code>] [-SubscriptionId <subscription-id>]
./add-user.sh [user-email-or-upn] [admin|user] [base-name] [environment] [location-code] [subscription-id]
```

Compile infrastructure before deployment when Azure CLI is available:

```text
az bicep build --file ./infra/main.bicep
```

## Conventions

- Use a single lowercase alphanumeric base name, 2-10 characters, and derive all Azure resource names from it. Default naming follows Microsoft resource abbreviations: `rg-<base>-<environment>-<region>`, `stapp-<base>-<environment>-<region>-<suffix>`, `cae-<base>-<environment>-<region>`, `ca-<base>-<environment>-<region>-api`, `acr<base><environment><suffix>`, and `log-<base>-<environment>-<region>`.
- Keep globally unique resource names lowercase and append the deployment's subscription-derived suffix. Do not add hyphens to Container Registry names.
- Use ESM JavaScript and Node standard-library HTTP APIs unless a library removes meaningful complexity.
- Keep API routes and their client calls aligned; update `app/config.example.js` and local startup behavior when the endpoint contract changes.
- Keep test coverage focused on request validation, persistence behavior, CORS, and route contracts.
- Use PowerShell 7+ syntax for deployment scripts and preserve their explicit command failure checks.
- Keep README explanations concise and update them whenever local startup or deployment behavior changes.
