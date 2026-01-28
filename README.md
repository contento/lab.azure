# Azure Lab

This repository contains examples and demonstrations for working with Azure services.

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────────┐
│                     Application Layer                      │
│  ┌────────────────────┐      ┌─────────────────────────┐   │
│  │  Python app.py     │      │  .NET Program.cs        │   │
│  └────────┬───────────┘      └───────────┬─────────────┘   │
│           │                              │                 │
│           ▼                              ▼                 │
│  ┌────────────────────┐      ┌─────────────────────────┐   │
│  │ Secret Store       │      │ Secret Store            │   │
│  │ (Factory Pattern)  │      │ (Local/Azure Mode)      │   │
│  └────────┬───────────┘      └───────────┬─────────────┘   │
└───────────┼──────────────────────────────┼─────────────────┘
            │                              │
     ┌──────┴──────┐                ┌─────┴──────┐
     │             │                │            │
     ▼             ▼                ▼            ▼
┌─────────┐  ┌──────────────┐ ┌─────────┐ ┌──────────────┐
│  Local  │  │    Azure     │ │  Local  │ │    Azure     │
│ Secrets │  │  Key Vault   │ │ Secrets │ │  Key Vault   │
│  (Dev)  │  │ (Production) │ │  (Dev)  │ │ (Production) │
└─────────┘  └──────┬───────┘ └─────────┘ └──────┬───────┘
                    │                            │
                    ▼                            ▼
            DefaultAzureCredential      DefaultAzureCredential
         (CLI, MI, SP, VS, etc.)     (CLI, MI, SP, VS, etc.)
```

## 📁 Projects

### Key Vault

Demonstrations of Azure Key Vault integration in multiple languages:

- **[Python](keyvault/python/)** - Python implementation using Azure SDK
- **.NET](keyvault/dotnet/)** - C# implementation using Azure SDK

Each project includes its own README with specific setup instructions and usage examples.

## 🚀 Getting Started

### Prerequisites

- An active Azure subscription
- Azure CLI installed and configured
- Appropriate SDK for your chosen language:
  - Python 3.7+ and pip
  - .NET 8.0+ SDK

### Azure Setup

1. Log in to Azure:
   ```bash
   az login
   ```

2. Create a resource group (if needed):
   ```bash
   az group create --name <resource-group-name> --location <location>
   ```

3. Follow the specific instructions in each project's README for service-specific setup.

## 📚 Documentation

- [Azure Key Vault Documentation](https://docs.microsoft.com/azure/key-vault/)
- [Azure Python SDK](https://docs.microsoft.com/python/api/overview/azure/)
- [Azure .NET SDK](https://docs.microsoft.com/dotnet/api/overview/azure/)

## 🤝 Contributing

Feel free to explore, learn, and contribute to these examples!

## 📝 License

This project is open source and available for educational purposes.
