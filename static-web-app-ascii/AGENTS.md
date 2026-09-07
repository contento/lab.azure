# Typecast Agent Guide

## Scope

This directory is an independent Azure Static Web Apps sample. Keep changes inside this module unless the task explicitly requires a workspace-level update. Do not alter the existing `keyvault/` samples when working on Typecast.

## Layout

- `app/`: plain browser HTML, CSS, JavaScript, and Static Web Apps configuration.
- `api/`: Node.js Azure Functions v4 API. This is the only location for ASCII generation, authorization decisions, and Azure Blob Storage access.
- `infra/`: Bicep provisioning and PowerShell 7+ deployment automation.

## Security Rules

- Treat all browser-provided identity and role data as untrusted. Derive the Entra object ID and roles from the Static Web Apps client principal in the API.
- Do not move `figlet`, Blob Storage operations, storage credentials, or authorization logic into `app/`.
- Use `DefaultAzureCredential` and the Static Web App managed identity for production Blob access. Never add storage account keys or connection strings to source control.
- Keep `api/local.settings.json`, client secrets, and Static Web Apps deployment tokens out of the repository.
- Users may only list or delete their own session paths. Admins may inspect all sessions but must remain read-only.

## Commands

Run these commands from `api/` after installing dependencies:

```text
npm test
npm run lint
```

Run from the module root when Azure CLI is available:

```text
az bicep build --file ./infra/main.bicep
pwsh ./deploy.ps1 -BaseName <name> [-Environment dev|test|prod] [-Location <azure-region>] [-LocationCode <region-code>] [-SubscriptionId <subscription-id>]
```

## Conventions

- Use one lowercase alphanumeric base name, 2-10 characters, and derive all Azure resource and Entra display names from it. Default naming follows Microsoft resource abbreviations: `rg-<base>-<environment>-<region>`, `stapp-<base>-<environment>-<region>-<suffix>`, `st<base><environment><suffix>`, `grp-<base>-<environment>-<region>-admins`, `grp-<base>-<environment>-<region>-users`, and `app-<base>-<environment>-<region>-swa`.
- Keep globally unique resource names lowercase and append the subscription-derived suffix. Do not add hyphens to Storage account names.
- Use ESM JavaScript and the Azure Functions v4 programming model.
- Keep tests focused in `api/test/` and cover authentication, authorization, input validation, and ownership boundaries for server-side changes.
- Use PowerShell 7+ syntax in `infra/deploy.ps1`.
- The checked-in `app/staticwebapp.config.json` intentionally contains `__TENANT_ID__`. `deploy.ps1` substitutes it only while publishing and restores the template afterward.
- Preserve the concise, security-focused explanations in `README.md` when behavior or deployment requirements change.
