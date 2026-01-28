using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Microsoft.Extensions.Configuration;

namespace AzureKeyVaultDemo;

class Program
{
    static async Task Main(string[] args)
    {
        try
        {
            // Load configuration
            var configuration = new ConfigurationBuilder()
                .SetBasePath(Directory.GetCurrentDirectory())
                .AddJsonFile("appsettings.json", optional: false, reloadOnChange: true)
                .AddEnvironmentVariables()
                .Build();

            var keyVaultUrl = configuration["KeyVault:VaultUrl"];

            if (string.IsNullOrEmpty(keyVaultUrl))
            {
                Console.WriteLine("Error: KeyVault:VaultUrl not found in configuration.");
                Console.WriteLine("Please update appsettings.json with your Azure Key Vault URL.");
                return;
            }

            Console.WriteLine("=== Azure Key Vault Demo ===");
            Console.WriteLine($"Key Vault URL: {keyVaultUrl}");
            Console.WriteLine();

            // Create a SecretClient using DefaultAzureCredential
            // DefaultAzureCredential will try multiple authentication methods:
            // 1. Environment variables
            // 2. Managed Identity (when running in Azure)
            // 3. Visual Studio
            // 4. Azure CLI
            // 5. Azure PowerShell
            // 6. Interactive browser (if enabled)
            var credential = new DefaultAzureCredential();
            var client = new SecretClient(new Uri(keyVaultUrl), credential);

            // Secret names to retrieve
            var secretNames = new[] { "rosina-username-dev", "rosina-password-dev" };

            Console.WriteLine("Retrieving secrets from Azure Key Vault...");
            Console.WriteLine();

            foreach (var secretName in secretNames)
            {
                try
                {
                    Console.WriteLine($"Fetching secret: {secretName}");
                    KeyVaultSecret secret = await client.GetSecretAsync(secretName);

                    Console.WriteLine($"  ✓ Secret Name: {secret.Name}");
                    Console.WriteLine($"  ✓ Secret Value: {MaskSecret(secret.Value)}");
                    Console.WriteLine($"  ✓ Enabled: {secret.Properties.Enabled}");
                    Console.WriteLine($"  ✓ Created: {secret.Properties.CreatedOn}");
                    Console.WriteLine($"  ✓ Updated: {secret.Properties.UpdatedOn}");
                    Console.WriteLine();
                }
                catch (Azure.RequestFailedException ex) when (ex.Status == 404)
                {
                    Console.WriteLine($"  ✗ Secret '{secretName}' not found in Key Vault");
                    Console.WriteLine();
                }
                catch (Exception ex)
                {
                    Console.WriteLine($"  ✗ Error retrieving secret '{secretName}': {ex.Message}");
                    Console.WriteLine();
                }
            }

            Console.WriteLine("=== Demo Complete ===");
            Console.WriteLine();
            Console.WriteLine("Note: To see the actual secret values, modify the MaskSecret method.");
        }
        catch (Azure.Identity.AuthenticationFailedException ex)
        {
            Console.WriteLine("Authentication failed!");
            Console.WriteLine($"Error: {ex.Message}");
            Console.WriteLine();
            Console.WriteLine("Authentication options:");
            Console.WriteLine("1. Azure CLI: Run 'az login' in your terminal");
            Console.WriteLine("2. Environment Variables: Set AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET");
            Console.WriteLine("3. Managed Identity: When running in Azure (App Service, Function, etc.)");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"An error occurred: {ex.Message}");
            Console.WriteLine($"Stack trace: {ex.StackTrace}");
        }
    }

    /// <summary>
    /// Masks the secret value for security (shows first 2 and last 2 characters)
    /// </summary>
    private static string MaskSecret(string value)
    {
        if (string.IsNullOrEmpty(value) || value.Length <= 4)
        {
            return "****";
        }

        return $"{value.Substring(0, 2)}****{value.Substring(value.Length - 2)}";
    }
}
