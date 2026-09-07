# Typecast Separate API TODO

## Deployment Verification

- [ ] Run `az bicep build --file ./infra/main.bicep` using the target Azure CLI version.
- [ ] Deploy to a non-production resource group with `./deploy.sh` or `pwsh ./deploy.ps1`.
- [ ] Confirm the Container App resolves and pulls the API image from the provisioned ACR.
- [ ] Confirm the generated `app/config.js` points to the Container App HTTPS endpoint and is not committed.
- [ ] Confirm only the deployed Static Web App origin is accepted by Container Apps ingress and API CORS headers.

## End-to-End Checks

- [ ] Open the deployed Static Web App and generate ASCII art through the separate Container Apps API.
- [ ] Confirm validation errors return usable client messages for blank, oversized, and unsupported-font requests.
- [ ] Verify history loads and deletion removes the selected session.
- [ ] Test the `OPTIONS` preflight, `GET /health`, `POST /generate`, and session endpoints from the deployed web origin.
- [ ] Confirm ACR credentials and Static Web Apps deployment tokens are absent from the repository, browser assets, and logs.

## Production Follow-Up

- [ ] Replace the Container App local filesystem session store with durable external storage before scaling beyond one replica or requiring retained history.
- [ ] Add authentication and server-side ownership enforcement before treating session history as private user data.
- [ ] Replace ACR admin credentials with managed identity image pulls.
- [ ] Add automated API route, persistence, validation, and CORS tests to the currently empty test suite.
- [ ] Add CI/CD with managed secrets and a controlled deployment approval path.
