import os
from typing import Dict, Optional, Protocol


class SecretStore(Protocol):
    """Protocol defining the interface for secret stores."""
    def get_secret(self, name: str) -> str:
        """Retrieve a secret by name."""
        ...


class LocalSecretStore:
    """Local secret store for development and testing."""

    def __init__(self, secrets: Optional[Dict[str, str]] = None) -> None:
        self._secrets = dict(secrets or {})

    def get_secret(self, name: str) -> str:
        if name not in self._secrets:
            raise KeyError(f"secret '{name}' not found in local store")
        return self._secrets[name]


class AzureSecretStore:
    """Azure Key Vault secret store."""

    def __init__(self, vault_name: str) -> None:
        try:
            from azure.identity import DefaultAzureCredential
            from azure.keyvault.secrets import SecretClient
        except Exception as e:
            raise ImportError(
                "azure packages are required to use AzureSecretStore; install requirements.txt"
            ) from e

        vault_url = f"https://{vault_name}.vault.azure.net"
        cred = DefaultAzureCredential()
        self._client = SecretClient(vault_url=vault_url, credential=cred)

    def get_secret(self, name: str) -> str:
        sec = self._client.get_secret(name)
        return sec.value


def make_secret_store_from_env() -> SecretStore:
    """Factory: choose AzureSecretStore when USE_AZURE=true and KEYVAULT_NAME set,
    otherwise a LocalSecretStore constructed from TEST_USERNAME/TEST_PASSWORD env vars.
    """
    use_azure = os.environ.get("USE_AZURE", "false").lower() in ("1", "true", "yes")
    if use_azure:
        vault_name = os.environ.get("KEYVAULT_NAME")
        if not vault_name:
            raise RuntimeError("USE_AZURE=true but KEYVAULT_NAME not set")
        return AzureSecretStore(vault_name=vault_name)

    # local fallback
    username = os.environ.get("TEST_USERNAME")
    password = os.environ.get("TEST_PASSWORD")
    secrets = {}
    if username is not None:
        secrets[os.environ.get("USERNAME_SECRET_NAME", "rosina-username-dev")] = username
    if password is not None:
        secrets[os.environ.get("PASSWORD_SECRET_NAME", "rosina-password-dev")] = password

    return LocalSecretStore(secrets)
