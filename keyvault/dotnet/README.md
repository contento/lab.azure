# Azure Key Vault Demo - .NET 10.0

This is a .NET console application demonstrating how to retrieve secrets from Azure Key Vault using the Azure SDK.

## Secrets Used

This demo retrieves the following secrets from Azure Key Vault:
- `rosina-username-dev`
- `rosina-password-dev`

## Prerequisites

1. **.NET 10.0 SDK** - [Download here](https://dotnet.microsoft.com/download/dotnet/10.0)
2. **Azure Subscription** - [Create free account](https://azure.microsoft.com/free/)
3. **Azure Key Vault** with the required secrets
4. **Authentication** - One of the following:
   - Azure CLI (`az login`)
   - Service Principal credentials
   - Managed Identity (when running in Azure)

## Setup Instructions

### 1. Install .NET 10.0 SDK

Download and install the .NET 10.0 SDK from:
https://dotnet.microsoft.com/download/dotnet/10.0

Verify installation:
```bash
dotnet --version
```

### 2. Create Azure Key Vault (if not exists)

```bash
# Login to Azure
az login

# Create resource group (if needed)
az group create --name rg-keyvault-demo --location eastus

# Create Key Vault
az keyvault create \
  --name your-keyvault-name \
  --resource-group rg-keyvault-demo \
  --location eastus

# Add secrets
az keyvault secret set --vault-name your-keyvault-name --name rosina-username-dev --value "your-username"
az keyvault secret set --vault-name your-keyvault-name --name rosina-password-dev --value "your-password"
```

### 3. Configure Application

**Option A: Azure Key Vault Mode**

Copy the example configuration and update with your Key Vault URL:
```bash
cp appsettings.example.json appsettings.json
# Edit appsettings.json with your Key Vault URL
```

Or use environment variables:
```bash
export KeyVault__VaultUrl="https://your-keyvault-name.vault.azure.net/"
```

**Option B: Local Development Mode**

For local testing without Azure:
```bash
export USE_LOCAL=true
export LOCAL_USERNAME="alice"
export LOCAL_PASSWORD="opensesame"
```

Or copy and edit the `.env.example` file:
```bash
cp .env.example .env
# Edit .env with your configuration
```

### 4. Grant Access Permissions

Give your Azure account access to the Key Vault secrets:

```bash
# Get your user principal ID
az ad signed-in-user show --query id -o tsv

# Grant Secret permissions
az keyvault set-policy \
  --name your-keyvault-name \
  --object-id <your-user-principal-id> \
  --secret-permissions get list
```

Or assign the "Key Vault Secrets User" role:
```bash
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee <your-email@domain.com> \
  --scope /subscriptions/<subscription-id>/resourceGroups/rg-keyvault-demo/providers/Microsoft.KeyVault/vaults/your-keyvault-name
```

## Running the Application

### Option 1: Using .NET CLI

```bash
# Restore dependencies
dotnet restore

# Build the project
dotnet build

# Run the application
dotnet run
```

### Option 2: Using Visual Studio

1. Open `AzureKeyVaultDemo.csproj` in Visual Studio
2. Press F5 to run with debugging or Ctrl+F5 to run without debugging

### Option 3: Using VS Code

1. Open the folder in VS Code
2. Press F5 to run

## Authentication Methods

The application uses `DefaultAzureCredential` which tries authentication methods in this order:

1. **Environment Variables** - Set these if using Service Principal:
   ```bash
   export AZURE_CLIENT_ID="<client-id>"
   export AZURE_TENANT_ID="<tenant-id>"
   export AZURE_CLIENT_SECRET="<client-secret>"
   ```

2. **Managed Identity** - Automatically works when running in Azure services (App Service, Functions, VMs, etc.)

3. **Azure CLI** - Run `az login` before running the app:
   ```bash
   az login
   dotnet run
   ```

4. **Visual Studio** - Sign in to Visual Studio with your Azure account

5. **Azure PowerShell** - Run `Connect-AzAccount`

## Project Structure

```
dotnet/
├── AzureKeyVaultDemo.csproj    # Project file with NuGet packages
├── Program.cs                   # Main application code
├── appsettings.json            # Configuration file (update with your Key Vault URL)
├── .gitignore                  # Git ignore file
└── README.md                   # This file
```

## NuGet Packages Used

- **Azure.Identity** (1.13.1) - Provides Azure authentication
- **Azure.Security.KeyVault.Secrets** (4.7.0) - Key Vault SDK for secrets
- **Microsoft.Extensions.Configuration** (10.0.0) - Configuration framework
- **Microsoft.Extensions.Configuration.Json** (10.0.0) - JSON configuration provider
- **Microsoft.Extensions.Configuration.EnvironmentVariables** (10.0.0) - Environment variables support

## Expected Output

```
=== Azure Key Vault Demo ===
Key Vault URL: https://your-keyvault-name.vault.azure.net/

Retrieving secrets from Azure Key Vault...

Fetching secret: rosina-username-dev
  ✓ Secret Name: rosina-username-dev
  ✓ Secret Value: ro****ev
  ✓ Enabled: True
  ✓ Created: 1/28/2026 10:30:00 AM
  ✓ Updated: 1/28/2026 10:30:00 AM

Fetching secret: rosina-password-dev
  ✓ Secret Name: rosina-password-dev
  ✓ Secret Value: Pa****23
  ✓ Enabled: True
  ✓ Created: 1/28/2026 10:31:00 AM
  ✓ Updated: 1/28/2026 10:31:00 AM

=== Demo Complete ===

Note: To see the actual secret values, modify the MaskSecret method.
```

## Security Best Practices

1. **Never commit secrets** - The `.gitignore` file excludes sensitive configuration files
2. **Use Managed Identity** - When running in Azure, use Managed Identity instead of credentials
3. **Principle of Least Privilege** - Grant only necessary permissions (Get, List for secrets)
4. **Rotate secrets regularly** - Use Key Vault's version management
5. **Enable soft-delete** - Protect against accidental deletion
6. **Monitor access** - Enable Key Vault logging and monitoring

## Troubleshooting

### Authentication Failed
- Ensure you're logged in: `az login`
- Check if you have permissions to the Key Vault
- Verify your Azure subscription is active

### Secret Not Found
- Verify the secret names are correct (case-sensitive)
- Check if secrets exist: `az keyvault secret list --vault-name your-keyvault-name`

### Connection Issues
- Verify the Key Vault URL in `appsettings.json`
- Check network connectivity
- Ensure Key Vault firewall allows your IP (if configured)

## Additional Resources

- [Azure Key Vault Documentation](https://docs.microsoft.com/azure/key-vault/)
- [Azure SDK for .NET Documentation](https://docs.microsoft.com/dotnet/azure/)
- [DefaultAzureCredential Documentation](https://docs.microsoft.com/dotnet/api/azure.identity.defaultazurecredential)
- [Key Vault Best Practices](https://docs.microsoft.com/azure/key-vault/general/best-practices)

## License

This is a demo application for educational purposes.
