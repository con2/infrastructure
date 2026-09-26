#!/usr/bin/env python3
# usage: eval $(uv run bin/garage_env.py PROFILE)
#        uv run bin/garage_env.py PROFILE -- aws s3 ls
# lets you access a Garage S3 API with AWS CLI or other tools that use AWS SDKs

import argparse
import os
import shlex
import subprocess
import sys
from dataclasses import dataclass

import yaml


@dataclass(frozen=True)
class Profile:
    garage_hostname: str
    # Credentials are read from group_vars/all/vault as
    # vault_garage_{vault_infix}_key_id and vault_garage_{vault_infix}_secret_key.
    vault_infix: str
    garage_region: str = "garage"


profiles = {
    "cnpg_backup": Profile(
        garage_hostname="piilo-s3.tracon.fi",
        vault_infix="s3",
    ),
    "minio_backup": Profile(
        garage_hostname="piilo-s3.tracon.fi",
        vault_infix="minio_backup",
    ),
    "garage_test": Profile(
        garage_hostname="garage.con2.fi",
        vault_infix="test",
    ),
}


def load_env(profile: Profile) -> dict[str, str]:
    vault_content = subprocess.check_output(
        ["ansible-vault", "view", "group_vars/all/vault"]
    )
    vault_dict = yaml.safe_load(vault_content)

    return {
        "AWS_ACCESS_KEY_ID": vault_dict[f"vault_garage_{profile.vault_infix}_key_id"],
        "AWS_SECRET_ACCESS_KEY": vault_dict[
            f"vault_garage_{profile.vault_infix}_secret_key"
        ],
        "AWS_DEFAULT_REGION": profile.garage_region,
        "AWS_ENDPOINT_URL": f"https://{profile.garage_hostname}",
    }


def main() -> None:
    argv = sys.argv[1:]
    if "--" in argv:
        separator = argv.index("--")
        profile_args, command = argv[:separator], argv[separator + 1 :]
    else:
        profile_args, command = argv, []

    parser = argparse.ArgumentParser(
        usage="%(prog)s PROFILE [-- COMMAND ...]",
        description=(
            "Print AWS environment export statements for a Garage profile, "
            "or run COMMAND with that environment set."
        ),
    )
    parser.add_argument("profile", choices=list(profiles))
    args = parser.parse_args(profile_args)

    env = load_env(profiles[args.profile])

    if command:
        os.execvpe(command[0], command, {**os.environ, **env})

    for key, value in env.items():
        print(f"export {key}={shlex.quote(value)}")


if __name__ == "__main__":
    main()
