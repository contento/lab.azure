# Typecast TODO

## Deployment Verification

- [ ] Install Azure CLI on the development machine and run `az bicep build --file ./infra/main.bicep`.
- [ ] Deploy into a non-production Azure resource group with `pwsh ./infra/deploy-infrastructure.ps1`.
- [ ] Confirm the Static Web App managed identity has `Storage Blob Data Contributor` on the created storage account.
- [ ] Confirm the deployment-created Entra app registration includes the production Static Web Apps callback URL and security group claims.
- [ ] Add one test account to the generated User group and one to the generated Admin group.

## End-to-End Checks

- [ ] As a User, generate ASCII art and confirm the API saves a JSON session under that account's Blob prefix.
- [ ] As a User, verify that history shows only that account's sessions and that deletion removes only an owned session.
- [ ] As an Admin, verify the read-only all-user session history is visible and no admin delete control is rendered.
- [ ] Confirm a new sign-in is required before Entra group membership changes appear in Static Web Apps roles.
- [ ] Verify browser bundles and deployed Static Web Apps settings do not expose storage keys, client secrets, or deployment tokens.

## Production Follow-Up

- [ ] Define Blob lifecycle retention and deletion policy appropriate to the intended data-retention requirements.
- [ ] Add CI/CD with a secret-managed Static Web Apps deployment token after selecting the source-control platform.
- [ ] Replace group-claim role resolution with Microsoft Graph lookup if expected Entra memberships can exceed token group-claim limits.
