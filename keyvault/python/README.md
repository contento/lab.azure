# Test Key Vault app

This small test app demonstrates reading two secrets (`rosina-username-dev` and
`rosina-password-dev`) from Azure Key Vault with a local fallback for development
and unit tests.

Quick steps

- **Optional:** Copy `.env.example` to `.env` and update with your values:
  ```bash
  cp .env.example .env
  # Edit .env with your configuration
  ```

- Install UV if you don't have it:
  ```bash
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ```

- Install runtime deps (optional, for real Azure use):
  ```bash
  uv sync
  ```

- Run locally using environment variables (no Azure):

```bash
export USE_AZURE=false
export TEST_USERNAME=alice
export TEST_PASSWORD=opensesame
uv run app.py --show
```

- To use Azure Key Vault (`chalo-dev-kv`):

```bash
export USE_AZURE=true
export KEYVAULT_NAME=chalo-dev-kv
uv run app.py
```

  Ensure Azure auth is configured for `DefaultAzureCredential` (via Azure CLI login or managed identity).

Run unit tests (no Azure dependency required):

```bash
uv run python -m unittest discover -v
```

Files

- `app.py` — CLI entry that reads username/password and prints a masked result.
- `keyvault.py` — small wrapper providing a KeyVault-backed or local secret store.
- `tests/test_keyvault.py` — unit tests using the local fallback.

Security note: This repo prints secrets only for demonstration when
`--show`/`TEST_*` are used. Avoid committing real secrets.
