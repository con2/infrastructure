# garage

Single-node [Garage](https://garagehq.deuxfleurs.fr/) S3-compatible object
store, used as an **off-site backup target** for CloudNativePG / Barman Cloud.
One Rust binary, one systemd unit, native S3 API. See
`object-storage-findings.md` in the repository root for the rationale and the
comparison against SeaweedFS.

## What this role does

- Installs the pinned `garage` binary to `/usr/local/bin/garage-<version>`
  (symlinked to `/usr/local/bin/garage`).
- Writes `/etc/garage/garage.toml` and a `garage.service` systemd unit running
  as the unprivileged `garage` user.
- Binds the S3 API, RPC and admin endpoints to **localhost only**. nginx
  terminates TLS on `:443` and proxies to the S3 API. No Garage port is exposed
  to the network, so no extra `ufw` rules are needed (nginx opens 80/443).
- Initialises the single-node cluster layout, creates the `cnpg-backups`
  bucket, and imports a fixed S3 access key (from the vault) with read/write/
  owner access to that bucket. All init steps are idempotent.

The nginx vhost (`server_name {{ garage_hostname }}`, e.g. `piilo-s3.tracon.fi`) sets
`client_max_body_size 0`, long proxy timeouts and `proxy_request_buffering off`
so multi-gigabyte base backups and restores stream straight through.

## Storage location

`garage_base_dir` (default `/var/lib/garage`) sets where metadata and data live
(`<base>/meta` and `<base>/data`). On `piilo` it is set to `/srv/garage`, a
dedicated volume, keeping Garage off the small root filesystem and fully
separate from the legacy Barman storage under `/var/lib/barman`.

If you ever place `garage_base_dir` under a directory the `garage` user cannot
traverse (e.g. another service's restrictive home), add the relevant group via
`garage_extra_groups` so the `garage` user can reach it.

## Requirements

This role expects the `nginx` and `letsencrypt` roles to have run earlier in
the play (it reuses the `restart nginx` handler and the
`/srv/letsencrypt/secrets/<host>/` certificate). The S3 endpoint hostname must
resolve to this server and have a Let's Encrypt certificate.

## CloudNativePG / Barman Cloud configuration

Point the object store at the public TLS endpoint and use **path-style** access
(Garage does not do virtual-hosted-style without extra DNS):

| Setting          | Value                                            |
|------------------|--------------------------------------------------|
| endpoint URL     | `https://piilo-s3.tracon.fi`                        |
| region           | `garage`                                         |
| bucket / path    | `cnpg-backups`                                   |
| force path style | `true` (`s3PathStyle: true`)                     |
| access key id    | `garage_s3_key_id` (vault)                       |
| secret access key| `garage_s3_secret_key` (vault)                   |

The credentials live in `group_vars/all/vault` as `vault_garage_s3_key_id` and
`vault_garage_s3_secret_key`; create the Kubernetes Secret CloudNativePG reads
from those values.

## Accessing Garage S3 with `aws` CLI

    eval $(uv run bin/garage_env.py)
    aws s3 ls
