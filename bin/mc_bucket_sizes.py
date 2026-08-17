#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["boto3"]
# ///
# usage: bin/mc_bucket_sizes.py [--mc-config PATH --mc-alias ALIAS]
# by default, connects using the standard AWS environment configuration
# (e.g. eval $(uv run bin/garage_env.py)); pass --mc-alias to instead use an
# alias from an mc config.json

import argparse
import json
from pathlib import Path

import boto3
from botocore.config import Config


def human_size(num_bytes):
    size = float(num_bytes)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB", "PiB"):
        if size < 1024 or unit == "PiB":
            return f"{size:.2f} {unit}"
        size /= 1024


def addressing_style(mc_path):
    return {"on": "path", "off": "virtual"}.get(mc_path, "auto")


def make_client(args):
    if not args.mc_alias:
        return boto3.client("s3")

    config = json.loads(args.mc_config.read_text())
    alias = config["aliases"][args.mc_alias]
    return boto3.client(
        "s3",
        endpoint_url=alias["url"],
        aws_access_key_id=alias["accessKey"],
        aws_secret_access_key=alias["secretKey"],
        config=Config(
            signature_version=alias.get("api", "s3v4"),
            s3={"addressing_style": addressing_style(alias.get("path", "auto"))},
        ),
    )


def bucket_size(client, bucket_name):
    total_bytes = 0
    object_count = 0
    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket_name):
        for obj in page.get("Contents", []):
            total_bytes += obj["Size"]
            object_count += 1
    return total_bytes, object_count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mc-config", type=Path, default=Path("~/.mc/config.json").expanduser()
    )
    parser.add_argument(
        "--mc-alias", help="use this mc config alias instead of the AWS environment"
    )
    args = parser.parse_args()

    client = make_client(args)
    print(client.meta.endpoint_url)

    grand_total_bytes = 0
    grand_total_objects = 0
    for bucket in client.list_buckets()["Buckets"]:
        total_bytes, object_count = bucket_size(client, bucket["Name"])
        grand_total_bytes += total_bytes
        grand_total_objects += object_count
        print(f"  {bucket['Name']:<40} {human_size(total_bytes):>12} ({object_count} objects)")
    print(f"  {'total':<40} {human_size(grand_total_bytes):>12} ({grand_total_objects} objects)")


if __name__ == "__main__":
    main()
