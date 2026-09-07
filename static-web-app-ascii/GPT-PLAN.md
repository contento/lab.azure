# Typecast Implementation Plan

## Goal

Build an Azure Static Web Apps application that converts user-entered text to ASCII art, retains each signed-in user's generated history in Azure Blob Storage, and provides separate User and Admin access through Microsoft Entra security groups.

## Decisions

- Use plain HTML, CSS, and browser JavaScript for the frontend. Node.js is used only for the Azure Functions API and tooling.
- Host `app/` and the Node.js Azure Functions API together in Azure Static Web Apps Standard. Browser API calls remain same-origin under `/api`.
- Use `figlet` only in the API so rendering logic and server-side validation are not delivered to the browser.
- Use Microsoft Entra ID custom authentication and two deployment-created security groups: `Admin` and `User`.
- Use a `rolesSource` API endpoint to map Entra group claims to Static Web Apps roles because group membership is not natively assigned to application roles by Static Web Apps.
- Store one JSON document per generation in Azure Blob Storage under `sessions/<Entra-object-id>/<session-id>.json`.
- Authenticate the API to Blob Storage with the Static Web App's system-assigned managed identity and `DefaultAzureCredential`. Do not use storage keys or connection strings in production.
- Let users list and delete only their own sessions. Let admins list all sessions without delete capability.
- Use Bicep for Azure resources and RBAC. Use PowerShell and Azure CLI for Entra group/app-registration work because it requires tenant permissions and the deployed app hostname.

## Build Sequence

1. Create the isolated `static-web-app-ascii/` module with static assets, Functions API, IaC, tests, and documentation.
2. Implement and test pure API services first: text/font validation, Figlet rendering, Static Web Apps principal parsing, role mapping, and ownership checks.
3. Add Blob session persistence using a server-controlled owner prefix and UUID file name. Keep all storage operations inside the API.
4. Add API endpoints for generation, personal history, owned-session deletion, admin history, and role resolution.
5. Configure `staticwebapp.config.json` with the custom Entra provider, `rolesSource`, authenticated routes, and admin route restrictions. Retain API-level authorization as the authoritative guard.
6. Build the static user interface: sign-in state, generator form, result actions, per-user history, and a conditionally rendered read-only admin history view.
7. Provision a Standard Static Web App, secure StorageV2 account, sessions container, and managed-identity Blob Data Contributor assignment through Bicep.
8. Create or reuse Entra groups and the single-tenant app registration from PowerShell, configure group claims and app settings, then publish frontend and API with a transient Static Web Apps deployment token.
9. Validate local code, Bicep compilation, deployment, Entra sign-in, User isolation, Admin visibility, and absence of credentials in browser assets.

## Security Boundaries

| Boundary | Implementation |
| --- | --- |
| Browser to API | Same-origin authenticated `/api` requests only; browser roles are for display and never authorize data access. |
| User identity | API decodes the Static Web Apps `x-ms-client-principal` header and uses the Entra object ID as the storage owner identifier. |
| Authorization | API checks session ownership for deletion and requires `admin` for all-user history. Static Web Apps route policy provides a second access layer. |
| Storage | Blob Storage is private; only the Static Web App managed identity receives the Blob Data Contributor role. |
| Secrets | Entra client secret and deployment token are kept in process/configuration only and never committed or sent to the frontend. |

## Verification Plan

1. Run `npm test` and `npm run lint` from `api/`.
2. Compile `infra/main.bicep` with `az bicep build`.
3. Parse `infra/deploy-infrastructure.ps1` with PowerShell 7+ and deploy to a non-production resource group.
4. Add separate test accounts to the generated User and Admin groups, then sign in again to refresh role claims.
5. Verify a User can generate, list, and delete only their own records.
6. Verify an Admin can view cross-user history but receives no deletion control.
7. Inspect deployed browser assets and Static Web Apps settings to ensure storage keys, client secrets, and deployment tokens are absent.

## Deferred Work

The tracked follow-up items live in [TODO.md](TODO.md), including retention rules, CI/CD, and a Microsoft Graph role-resolution alternative for Entra group-claim overage.
