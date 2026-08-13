#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["boto3"]
# ///
# usage: bin/mc_bucket_sizes.py [--config PATH] [--alias ALIAS]
# lists buckets and total object size per bucket for aliases in an mc config.json

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


def make_client(alias):
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
        "--config", type=Path, default=Path("~/.mc/config.json").expanduser()
    )
    parser.add_argument("--alias", help="only report on this alias")
    args = parser.parse_args()

    config = json.loads(args.config.read_text())
    aliases = config["aliases"]
    if args.alias:
        aliases = {args.alias: aliases[args.alias]}

    grand_total_bytes = 0
    for alias_name, alias in aliases.items():
        print(f"{alias_name} ({alias['url']})")
        client = make_client(alias)
        alias_total_bytes = 0
        for bucket in client.list_buckets()["Buckets"]:
            total_bytes, object_count = bucket_size(client, bucket["Name"])
            alias_total_bytes += total_bytes
            print(f"  {bucket['Name']:<40} {human_size(total_bytes):>12} ({object_count} objects)")
        print(f"  {'total':<40} {human_size(alias_total_bytes):>12}")
        grand_total_bytes += alias_total_bytes

    if len(aliases) > 1:
        print(f"grand total: {human_size(grand_total_bytes)}")


if __name__ == "__main__":
    main()
