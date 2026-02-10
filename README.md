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
  - Python 3.7+ and uv (recommended) or pip
  - .NET 8.0+ SDK

### UV Package Manager (Python Projects)

For Python projects, we use [uv](https://docs.astral.sh/uv/) - an extremely fast Python package installer and resolver written in Rust.

#### Installation

**macOS/Linux:**
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

**Windows:**
```powershell
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
```

**Using pip:**
```bash
pip install uv
```

#### Creating a Virtual Environment

```bash
# Create a virtual environment
uv venv

# Activate the virtual environment
# On macOS/Linux:
source .venv/bin/activate
# On Windows:
.venv\Scripts\activate
```

#### Installing Dependencies

```bash
# Install all dependencies from pyproject.toml
uv sync

# Add a new package
uv add <package-name>

# Add a development dependency
uv add --dev <package-name>

# Install dependencies without creating/updating lock file
uv pip install -r requirements.txt  # (legacy support)
```

#### Running Python Scripts

```bash
# Run a script directly (no need to activate venv)
uv run app.py

# Run with arguments
uv run app.py --show

# Run a specific module
uv run -m pytest
```

#### Why UV?

- **10-100x faster** than pip for package installation
- **Built-in virtual environment** management
- **Drop-in replacement** for pip
- **Resolves dependencies** correctly and quickly
- **Zero config** - works out of the box

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
