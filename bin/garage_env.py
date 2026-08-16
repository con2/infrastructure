#!/usr/bin/env python3
# usage: eval $(uv run bin/garage_env.py [s3|minio_backup])
# lets you access the garage S3 API with AWS CLI or other tools that use AWS SDKs

import subprocess
import sys

import yaml


def main(
    vault_infix="s3",
    *,
    garage_region="garage",
    garage_hostname="piilo-s3.tracon.fi",
):
    vault_content = subprocess.check_output(
        ["ansible-vault", "view", "group_vars/all/vault"]
    )
    vault_dict = yaml.safe_load(vault_content)

    env = {
        "AWS_ACCESS_KEY_ID": vault_dict[f"vault_garage_{vault_infix}_key_id"],
        "AWS_SECRET_ACCESS_KEY": vault_dict[f"vault_garage_{vault_infix}_secret_key"],
        "AWS_DEFAULT_REGION": garage_region,
        "AWS_ENDPOINT_URL": f"https://{garage_hostname}",
    }

    for key, value in env.items():
        print(f"export {key}={value}")


if __name__ == "__main__":
    main(*sys.argv[1:])
