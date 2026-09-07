# Typecast: Azure Static Web Apps ASCII Generator

Typecast is a plain HTML, CSS, and JavaScript application hosted by Azure Static Web Apps. Its Node.js Functions API generates ASCII art and stores each authenticated user's generation history in Azure Blob Storage. The browser never renders ASCII art, reads Blob Storage, or receives storage credentials.

## Architecture

- **Static frontend:** `app/` is served by Azure Static Web Apps.
- **API:** `api/` contains Node.js Azure Functions served from the same origin under `/api`.
- **Authentication:** a custom Microsoft Entra ID provider uses the deployment-created security groups to assign `admin` and `user` application roles.
- **Storage:** the Static Web App's system-assigned managed identity has `Storage Blob Data Contributor` on the storage account. Session JSON documents are stored under `sessions/<Entra-object-id>/<session-id>.json`.
- **Authorization:** every API request derives its owner ID from the signed-in Static Web Apps principal. Users can view/delete only their own sessions; admins can also view all sessions without deleting them.

## Prerequisites

- Node.js 20 or 22 LTS and npm
- Azure CLI, authenticated with `az login`
- PowerShell 7+
- An Azure subscription where you can create resource groups, Static Web Apps, Storage accounts, and role assignments
- Microsoft Entra permissions to create app registrations, create groups, and configure group claims. Tenant policy may require an Entra administrator to perform these steps.

The deployment script downloads the Static Web Apps CLI through `npx`; no global SWA CLI installation is required.

## Local development

```powershell
cd api
npm install
npm test
Copy-Item local.settings.example.json local.settings.json
npx --package @azure/static-web-apps-cli swa start ../app --api-location . --swa-config-location ../local
```

The checked-in local settings enable a fixed local developer identity and write session JSON to `api/.sessions/`; neither Microsoft Entra ID nor Azure Storage is used during this workflow. `local/staticwebapp.config.json` keeps API routes open for the local server only. Do not use it for deployment.

Production continues to require a Static Web Apps Entra principal and uses managed-identity Blob access. Deploy to a test environment to validate real group claims and managed-identity behavior.

## Deploy

Choose globally unique values for the Static Web App and storage account names, then run:

```powershell
pwsh ./infra/deploy.ps1 `
  -ResourceGroupName rg-typecast-dev `
  -StaticWebAppName typecast-your-unique-name `
  -StorageAccountName typecastunique123
```

The script provisions the Standard Static Web App, Storage account, sessions container, and Blob RBAC assignment from `infra/main.bicep`. It then creates or reuses two Entra security groups, configures a single-tenant app registration with group claims, sets the required Static Web App application settings, and deploys `app/` plus `api/` using a deployment token held only in process memory.

Add people to the reported `*-Admins` or `*-Users` group using your tenant's approved membership process. Group changes can require a fresh sign-in before new claims are visible.

## Validate infrastructure

With Azure CLI installed, compile the template before provisioning:

```powershell
az bicep build --file ./infra/main.bicep
```

Then run the deployment script against a non-production resource group. Verify both group paths with separate accounts: user generation/history/deletion isolation, admin read-only global history, and Blob records owned by the authenticated Entra object ID.

## Security notes

- Do not commit `api/local.settings.json`, deployment tokens, or Entra client secrets.
- `staticwebapp.config.json` contains a deployment-time tenant placeholder. `deploy.ps1` replaces it only while publishing and restores the checked-in template immediately afterward.
- This lab's two-group claim configuration is suitable for normal memberships. Large Entra group claim sets can trigger claim overage and should use a Microsoft Graph role-resolution design in production.
