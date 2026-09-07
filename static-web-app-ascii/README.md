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

Run one of the local helpers from the project root. Each creates `api/local.settings.json` from the local-only template when it is absent, installs API dependencies when needed, and starts the emulator at `http://localhost:4280`.

```bash
./start-local.sh
```

```powershell
pwsh ./start-local.ps1
```

The local helpers require Node.js 20 or 22 LTS, npm, and Azure Functions Core Tools v4 (`func`). They start `func` directly and configure SWA to proxy API requests to it, avoiding the SWA CLI's automatic Core Tools download. The checked-in local settings enable a fixed local developer identity and write session JSON to `api/.sessions/`; neither Microsoft Entra ID nor Azure Storage is used during this workflow. `local/staticwebapp.config.json` keeps API routes open for the local server only. Do not use it for deployment.

Production continues to require a Static Web Apps Entra principal and uses managed-identity Blob access. Deploy to a test environment to validate real group claims and managed-identity behavior.

## Deploy

The checked-in `infra/parameters.dev.bicepparam` supplies the default base name (`asciitype`), environment (`dev`), location (`eastus2`), region code (`eus2`), and active development subscription. Copy `infra/parameters.template.bicepparam` for a future subscription or environment.

### 1. Code deployment (`app/` and `api/`)
Deploy or update the frontend assets and Azure Functions API code to an existing Static Web App:

```bash
./deploy-code.sh
```

```powershell
pwsh ./deploy-code.ps1
```

### 2. Infrastructure deployment
Provision or update Azure Resource Groups, Storage accounts, Static Web Apps, Entra ID groups, and app registrations:

```bash
./infra/deploy-infrastructure.sh
```

```powershell
pwsh ./infra/deploy-infrastructure.ps1
```

`infra/deploy-infrastructure.ps1` automatically adds the active Azure CLI user to the environment's `*-admins` and `*-users` security groups.

### 3. Add users to application roles
To assign `admin` or `user` roles to yourself or another user by email/UPN:

```bash
./add-user.sh [user-email-or-upn] [admin|user]
```

```powershell
pwsh ./add-user.ps1 [-User <email-or-upn>] [-Role admin|user]
```

Omit the user parameter to assign the currently active Azure CLI user. Group changes require signing out and in again on the app before new claims are reflected.

## Validate infrastructure

With Azure CLI installed, compile the template before provisioning:

```powershell
az bicep build --file ./infra/main.bicep
```

Then run the deployment script against a non-production resource group. Verify both group paths with separate accounts: user generation/history/deletion isolation, admin read-only global history, and Blob records owned by the authenticated Entra object ID.

## Security notes

- Do not commit `api/local.settings.json`, deployment tokens, or Entra client secrets.
- `staticwebapp.config.json` contains a deployment-time tenant placeholder. `deploy-code.ps1` replaces it only while publishing and restores the checked-in template immediately afterward.
- This lab's two-group claim configuration is suitable for normal memberships. Large Entra group claim sets can trigger claim overage and should use a Microsoft Graph role-resolution design in production.
