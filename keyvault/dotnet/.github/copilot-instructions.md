# Copilot / AI agent instructions

Purpose: Help an AI agent quickly discover project structure, build
and test commands, important integration points, and project
conventions so the agent can make safe, repository-appropriate
changes.

Discovery checklist (what the agent should look for first):

- Primary language manifests: `*.csproj`, `*.sln`, `packages.config`, `Directory.Build.props`
- Entry points and main packages: `Program.cs`, `Startup.cs`, `src/`, `Controllers/`
- CI and build config: `.github/workflows/`, `azure-pipelines.yml`, `Dockerfile`, `Makefile`
- Runtime/config files: `appsettings.json`, `appsettings.Development.json`, `.env`, `launchSettings.json`
- Tests and test runners: `*Tests/`, `*.Tests.csproj`, `xunit.runner.json`, `coverlet.runsettings`

Extraction steps (concrete, repeatable):

1. Grep for `.csproj` and `.sln` files to identify the project structure
2. If `README.md` exists, read it for language, setup, and run
   instructions. If missing, try `docs/` or `CONTRIBUTING.md`
3. Look for CI workflows under `.github/workflows/` to capture the
   canonical build/test commands run in CI
4. Inspect `Dockerfile`(s) and `Makefile`(s) for build and run steps

What to document here (agents should write or update these fields):

- Primary language: **C# / .NET 10.0**
- Package manager: **NuGet** (via dotnet CLI)
- Build command(s): 
  - `dotnet restore` — Restore dependencies
  - `dotnet build` — Build the project
  - `dotnet build --configuration Release` — Release build
- Test command(s): `dotnet test` (when tests are added)
- Dev/run command(s):
  - Local run: `dotnet run`
  - With authentication: Ensure `az login` is executed first
  - Production: `dotnet run --configuration Release`
- Key entry files / services:
  - `Program.cs` — Main entry point, Azure Key Vault integration
  - `appsettings.json` — Configuration (Key Vault URL)
  - `AzureKeyVaultDemo.csproj` — Project file with NuGet dependencies
  - `dotnet.sln` — Solution file
- Important env vars (or add `.env.example`):
  - `KeyVault__VaultUrl` — Azure Key Vault URL (overrides appsettings.json)
  - `AZURE_CLIENT_ID` — Service Principal App ID (optional)
  - `AZURE_TENANT_ID` — Azure AD Tenant ID (optional)
  - `AZURE_CLIENT_SECRET` — Service Principal Secret (optional)
  - Note: Uses `DefaultAzureCredential` which tries multiple auth methods (CLI, Managed Identity, etc.)

Project-specific conventions (examples to replace with repo facts):

- This is a .NET console application demonstrating Azure Key Vault integration
- Uses Azure SDK packages: `Azure.Identity` and `Azure.Security.KeyVault.Secrets`
- Retrieves secrets: `rosina-username-dev` and `rosina-password-dev`
- Authentication via `DefaultAzureCredential` (prefers Azure CLI for local dev)
- Configuration follows .NET configuration patterns (appsettings.json + environment variables)
- Secrets are masked in console output for security

Coding style:

- Uses nullable reference types (`<Nullable>enable</Nullable>`)
- Async/await patterns for Azure SDK calls
- Try-catch blocks for Azure-specific exceptions
- XML documentation comments for public methods

Dependencies:

- `Azure.Identity` v1.13.1 — Authentication
- `Azure.Security.KeyVault.Secrets` v4.7.0 — Key Vault operations
- `Microsoft.Extensions.Configuration.*` v10.0.0 — Configuration management
