# Copilot / AI agent instructions

Purpose: Help an AI agent quickly discover project structure, build
and test commands, important integration points, and project
conventions so the agent can make safe, repository-appropriate
changes.

Discovery checklist (what the agent should look for first):

- Primary language manifests: `package.json`, `pyproject.toml`,
  `requirements.txt`, `go.mod`, `Cargo.toml`, `pom.xml`, `Gemfile`.
- Entry points and main packages: `src/`, `cmd/`, `app/`, `main.go`,
  `__main__.py`, `server/`, `index.js`.
- CI and build config: `.github/workflows/`, `Jenkinsfile`, `Dockerfile`,
  `Makefile`, `build.sh`.
- Runtime/config files: `.env`, `.env.example`, `config/`, `helm/`,
  `terraform/`.
- Tests and test runners: `tests/`, `spec/`, `pytest.ini`, `jest.config.js`.

Extraction steps (concrete, repeatable):

1. Grep for top-level manifests listed above and open the first match.
2. If `README.md` exists, read it for language, setup, and run
   instructions. If missing, try `docs/` or `CONTRIBUTING.md`.
3. Look for CI workflows under `.github/workflows/` to capture the
   canonical build/test commands run in CI.
4. Inspect Dockerfile(s) and Makefile(s) for build and run steps.

What to document here (agents should write or update these fields):

- Primary language: **Python 3.x**
- Package manager: **UV** (fast Python package installer)
- Build command(s): `uv pip install -r requirements.txt`
- Test command(s): `uv run python -m unittest discover -v`
- Dev/run command(s):
  - Local testing: `export USE_AZURE=false && export TEST_USERNAME=alice && export TEST_PASSWORD=opensesame && uv run app.py --show`
  - Azure Key Vault: `export USE_AZURE=true && export KEYVAULT_NAME=chalo-dev-kv && uv run app.py`
- Key entry files / services:
  - `app.py` — CLI entry point
  - `keyvault.py` — Secret store wrapper (Azure + local fallback)
  - `tests/test_keyvault.py` — Unit tests
- Important env vars (or add `.env.example`):
  - `USE_AZURE` — Set to `true` to use Azure Key Vault, `false` for local testing
  - `KEYVAULT_NAME` — Azure Key Vault name (e.g., `chalo-dev-kv`)
  - `TEST_USERNAME` / `TEST_PASSWORD` — Local fallback secrets for development
  - `USERNAME_SECRET_NAME` / `PASSWORD_SECRET_NAME` — Override secret names (defaults: `rosina-username-dev`, `rosina-password-dev`)

Project-specific conventions (examples to replace with repo facts):

- This is a small demo/test project for Azure Key Vault integration.
- Secrets retrieved from Key Vault: `rosina-username-dev` and `rosina-password-dev`.
- Azure Key Vault URL: `https://chalo-dev-kv.vault.azure.net/`
- Uses `DefaultAzureCredential` for Azure authentication.
- Keep changes minimal and focused on the Key Vault integration pattern.
- Run unit tests before committing changes.

Safety and review guidance for the agent:

- If tests exist, run the test command(s) locally before proposing
  a change. Do not open PRs that break CI.
- Prefer minimal, well-scoped changes. If unsure about architecture
  intent, add a clear TODO and a comment asking for human review.
- When touching infra (Dockerfile, CI workflow), include an explicit
  summary of potential deployment implications in the PR description.

If this repo is private or uses external services (cloud, keyvaults,
secret stores): do not create or leak credentials. Prefer using
configuration variables and update README with required secrets and
how to obtain them.

**This project uses Azure Key Vault (`chalo-dev-kv`)** for production secrets.
Never commit real secrets to the repository. Use environment variables
or Azure authentication for accessing secrets.

Next steps for a human maintainer:

- ✅ README.md exists with language, build, test, and run commands.
- ✅ Project info has been populated above.
- Consider adding `.env.example` with template environment variables.

---
Generated: please review and tailor to this project.
