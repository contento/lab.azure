# Azure Static Web Apps Authentication and Storage Fixes

This guide documents the production issues diagnosed in this sample and the fixes that can be reused in another Azure Static Web Apps application with a Node.js Functions API, Microsoft Entra ID sign-in, and Azure Blob Storage.

## Symptoms and Root Causes

### Static Web Apps shows `401: Unauthorized` at the Entra callback

Check the Entra sign-in logs for the application ID. Error `700054` with this message identifies the problem:

```text
response_type 'id_token' is not enabled for the application
```

Static Web Apps uses a hybrid callback and requests:

```text
response_type=code+id_token
```

The Entra app registration must allow ID-token issuance. A successful password or MFA step does not mean the Static Web Apps callback can finish; the callback still fails if the ID token is not issued.

### The callback loops or fails while using a custom `rolesSource`

A Static Web Apps `rolesSource` endpoint is called by the platform while authentication is being completed. Protecting that endpoint with the normal authenticated API rule creates a circular dependency. In addition, managed Static Web Apps API routing can return a gateway-level `404` for the role-source call even when the Functions inventory shows the function.

For this pattern, do not use `rolesSource` for application authorization. Let authentication establish the Static Web Apps principal, then call the authenticated API to resolve application roles from trusted server-side group claims.

### The app loads, but generation fails with `DefaultAzureCredential`

A managed Static Web Apps API can run without an identity endpoint available to the Node.js process. In that situation, `DefaultAzureCredential` cannot use the Static Web App system identity and reports that no credential is available.

A system-assigned identity and a correct role assignment in ARM are not sufficient if the API runtime cannot obtain a managed-identity token.

## Fix the Entra Callback

### 1. Verify the redirect URI

The Entra app registration must contain exactly:

```text
https://<static-app-hostname>/.auth/login/aad/callback
```

Check it with Azure CLI:

```bash
az ad app show \
  --id <client-id> \
  --query '{redirectUris:web.redirectUris,implicitGrant:web.implicitGrantSettings}' \
  --output json
```

### 2. Enable ID-token issuance

Using Azure CLI:

```bash
az ad app update \
  --id <client-id> \
  --enable-id-token-issuance true
```

Verify the result:

```bash
az ad app show \
  --id <client-id> \
  --query web.implicitGrantSettings.enableIdTokenIssuance \
  --output tsv
```

The result must be `true`.

The deployment script should make this setting idempotent so a later infrastructure run does not remove it:

```powershell
Invoke-Az @(
    "ad", "app", "update", "--id", $appId,
    "--set", "groupMembershipClaims=SecurityGroup",
    "--enable-id-token-issuance", "true"
)
```

### 3. Ensure the enterprise application exists

The app registration needs a service principal in the tenant:

```bash
az ad sp list \
  --filter "appId eq '<client-id>'" \
  --query '[0].{id:id,enabled:accountEnabled}' \
  --output json
```

Create it when absent:

```bash
az ad sp create --id <client-id>
```

`appRoleAssignmentRequired` should normally be `false` unless the application is intentionally configured to require explicit enterprise-application assignments.

### 4. Keep Static Web Apps routes simple

The public frontend should remain public. Protect API routes with the authenticated role, and protect administrator routes with the application role:

```json
{
  "routes": [
    { "route": "/api/sessions/admin", "allowedRoles": ["admin"] },
    { "route": "/api/*", "allowedRoles": ["authenticated"] }
  ],
  "auth": {
    "identityProviders": {
      "azureActiveDirectory": {
        "registration": {
          "openIdIssuer": "https://login.microsoftonline.com/__TENANT_ID__/v2.0",
          "clientIdSettingName": "AZURE_CLIENT_ID",
          "clientSecretSettingName": "AZURE_CLIENT_SECRET"
        }
      }
    }
  }
}
```

Do not add a `rolesSource` callback unless its lifecycle and platform routing are specifically tested. Resolve application roles in an authenticated API instead.

The frontend should fetch roles after authentication:

```javascript
const roles = (await request("/api/GetRoles")).roles;
```

The API must derive the object ID and groups from `x-ms-client-principal`; never trust browser-provided user IDs or role values.

## Fix Blob Storage Credential Acquisition

### Preferred architecture

If the API runs in a hosting environment that exposes managed identity, keep this pattern:

```javascript
const serviceClient = new BlobServiceClient(
  `https://${storageAccountName}.blob.core.windows.net`,
  new DefaultAzureCredential()
);
```

Grant the runtime identity the least-privileged role at the storage-account scope:

```bash
az role assignment create \
  --assignee-object-id <runtime-principal-object-id> \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope <storage-account-resource-id>
```

Never put a storage account key or connection string in source control.

### Managed Static Web Apps API limitation

For a managed Static Web Apps API, verify that the API process actually has a managed-identity endpoint. If it does not, `DefaultAzureCredential` cannot use the Static Web App resource identity even when the ARM role assignment is correct.

This sample uses the existing Entra application as an environment credential for the API because it already has a client ID and secret required by Static Web Apps authentication. The infrastructure script:

1. Sets `AZURE_TENANT_ID`.
2. Grants the Entra application's service principal `Storage Blob Data Contributor` on the storage account.
3. Keeps the Static Web App managed-identity role assignment as well.
4. Leaves the API on `DefaultAzureCredential`, which can then use the environment credential.

The relevant application settings are:

```text
AZURE_CLIENT_ID=<entra-app-client-id>
AZURE_CLIENT_SECRET=<secret-value>
AZURE_TENANT_ID=<tenant-id>
STORAGE_ACCOUNT_NAME=<storage-account-name>
SESSIONS_CONTAINER_NAME=sessions
```

Treat `AZURE_CLIENT_SECRET` as a secret. Never print it, commit it, or place it in documentation. Rotate it during infrastructure deployment and keep it in the Static Web App application settings only.

For a higher-isolation production design, use a separate workload identity or a linked Function App with managed identity instead of reusing the Entra authentication application for storage access.

## Deployment and Verification Checklist

1. Confirm the redirect URI matches the deployed hostname exactly.
2. Enable Entra ID-token issuance and verify it returns `true`.
3. Confirm the enterprise application/service principal exists and is enabled.
4. Confirm the user belongs to the intended security group.
5. Remove `rolesSource` while diagnosing callback failures.
6. Deploy the frontend configuration and API together.
7. Confirm the storage credential settings exist without printing secret values.
8. Confirm the API identity has `Storage Blob Data Contributor`.
9. Sign in through a new authorization URL. Do not refresh an old callback URL.
10. Test one generation, history listing, deletion, and administrator read-only history.

Useful checks:

```bash
az ad app show --id <client-id> \
  --query 'web.implicitGrantSettings' --output json

az staticwebapp appsettings list \
  --name <static-app-name> \
  --resource-group <resource-group> \
  --query 'properties | {clientId:AZURE_CLIENT_ID,tenantId:AZURE_TENANT_ID,storage:STORAGE_ACCOUNT_NAME}' \
  --output json

az role assignment list \
  --scope <storage-account-resource-id> \
  --assignee-object-id <principal-object-id> \
  --query '[].roleDefinitionName' \
  --output tsv
```

If authentication still fails, inspect Entra sign-in logs instead of repeatedly retrying the callback:

```bash
az rest --method get \
  --url "https://graph.microsoft.com/v1.0/auditLogs/signIns?\$filter=appId%20eq%20'<client-id>'&\$orderby=createdDateTime%20desc&\$top=10" \
  --query 'value[].{time:createdDateTime,error:status.errorCode,reason:status.failureReason}' \
  --output json
```

Common useful error codes include:

- `700054`: enable ID-token issuance.
- `401` from the Static Web Apps callback after successful Entra sign-in: inspect the app registration, redirect URI, client secret, and stale callback transaction.
- `CredentialUnavailableError`: verify whether the API runtime exposes managed identity; if it does not, configure a supported environment/workload credential and grant it Blob Data Contributor.
