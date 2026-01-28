import argparse
import os
from keyvault import make_secret_store_from_env


def mask_secret(s: str) -> str:
    if not s:
        return ""
    if len(s) <= 4:
        return "*" * len(s)
    return s[:2] + "*" * (len(s) - 4) + s[-2:]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--show", action="store_true", help="Print secrets (only for testing)")
    args = p.parse_args()

    store = make_secret_store_from_env()
    uname_name = os.environ.get("USERNAME_SECRET_NAME", "rosina-username-dev")
    pwd_name = os.environ.get("PASSWORD_SECRET_NAME", "rosina-password-dev")

    try:
        username = store.get_secret(uname_name)
    except Exception as e:
        print(f"failed to read username secret '{uname_name}': {e}")
        return 2

    try:
        password = store.get_secret(pwd_name)
    except Exception as e:
        print(f"failed to read password secret '{pwd_name}': {e}")
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
