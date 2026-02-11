import argparse
import os
import sys
from secret_stores import make_secret_store_from_env


def mask_secret(s: str) -> str:
    if not s:
        return ""
    if len(s) <= 4:
        return "*" * len(s)
    return s[:2] + "*" * (len(s) - 4) + s[-2:]


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--show", action="store_true", help="Print secrets (only for testing)")
    args = p.parse_args()

    # Initialize secret store
    try:
        store = make_secret_store_from_env()
    except RuntimeError as e:
        print(f"Configuration error: {e}", file=sys.stderr)
        print("Hint: Set USE_AZURE=false for local mode or ensure KEYVAULT_NAME is set", file=sys.stderr)
        return 1
    except ImportError as e:
        print(f"Import error: {e}", file=sys.stderr)
        print("Hint: Install dependencies with: pip install -r requirements.txt", file=sys.stderr)
        return 1

    uname_name = os.environ.get("USERNAME_SECRET_NAME", "rosina-username-dev")
    pwd_name = os.environ.get("PASSWORD_SECRET_NAME", "rosina-password-dev")

    # Retrieve username
    try:
        username = store.get_secret(uname_name)
    except KeyError as e:
        print(f"Secret not found: {e}", file=sys.stderr)
        print(f"Hint: Ensure secret '{uname_name}' exists in your Key Vault or set TEST_USERNAME for local mode", file=sys.stderr)
        return 2
    except Exception as e:
        print(f"Failed to read username secret '{uname_name}': {type(e).__name__}: {e}", file=sys.stderr)
        if "authentication" in str(e).lower() or "credential" in str(e).lower():
            print("Hint: Run 'az login' or check your Azure credentials", file=sys.stderr)
        return 2

    # Retrieve password
    try:
        password = store.get_secret(pwd_name)
    except KeyError as e:
        print(f"Secret not found: {e}", file=sys.stderr)
        print(f"Hint: Ensure secret '{pwd_name}' exists in your Key Vault or set TEST_PASSWORD for local mode", file=sys.stderr)
        return 3
    except Exception as e:
        print(f"Failed to read password secret '{pwd_name}': {type(e).__name__}: {e}", file=sys.stderr)
        if "authentication" in str(e).lower() or "credential" in str(e).lower():
            print("Hint: Run 'az login' or check your Azure credentials", file=sys.stderr)
        return 3

    if args.show:
        print("username:", username)
        print("password:", password)
    else:
        print("username:", mask_secret(username))
        print("password:", mask_secret(password))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
