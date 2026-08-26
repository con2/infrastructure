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
- Does the same for a second bucket, `minio-backup` — the destination for the
  off-site `minio.con2.fi` backup mirror. That mirror itself runs as Kubernetes
  CronJobs in the `qb` cluster, not on this host; see
  `infrastructure/kubernetes/minio-backup.*`. This host only ever provisions the
  bucket and key — keeping Garage a "dumb" S3 target that could be swapped for
  any other S3-compatible store without touching the backup logic.

The nginx vhost (`server_name {{ garage_hostname }}`, e.g. `piilo-s3.tracon.fi`) sets
`client_max_body_size 0`, long proxy timeouts and `proxy_request_buffering off`
so multi-gigabyte base backups and restores stream straight through.

## Logging

Garage logs every S3 request at `info` level, which floods syslog/journald on
a busy host. `garage.service.j2` sets `RUST_LOG=garage=info,garage_api_common=warn`
so only 5xx server errors are logged (Garage logs 4xx client errors at `info`
too, so those are silenced along with the per-request access-log lines — trade
that back to `garage_api_common=info` if you need to see them), and writes
stdout/stderr straight to `{{ garage_log_file }}` instead of the journal, with
`/etc/logrotate.d/garage` rotating it daily (or at 100M) and keeping 7 copies.

`garage_log_dir` is created by this role (same task as the data/metadata
dirs), not by systemd's `LogsDirectory=` — that directive sets the directory
up too late for `StandardOutput=append:`/`StandardError=append:` to use it
([systemd/systemd#27591](https://github.com/systemd/systemd/issues/27591)),
so the unit fails to start with "Failed to set up standard output" if the
directory isn't already there.

## Storage location

`garage_base_dir` (default `/var/lib/garage`) sets where metadata and data live
(`<base>/meta` and `<base>/data`). On `piilo` it is set to `/srv/garage`, a
dedicated volume, keeping Garage off the small root filesystem and fully
separate from the legacy Barman storage under `/var/lib/barman`.

If you ever place `garage_base_dir` under a directory the `garage` user cannot
traverse (e.g. another service's restrictive home), add the relevant group via
`garage_extra_groups` so the `garage` user can reach it.

## Metadata backup

This role installs a script into `/etc/pre-backup.d` (see the `prebackup`
role) that runs `garage meta snapshot` to take a consistent live snapshot of
the LMDB metadata database, then copies the latest snapshot to
`/var/backups/garage/{{ garage_hostname }}-metadata`. The external BackupPC
setup picks that path up along with the rest of `/var/backups`. The bucket
data under `garage_data_dir` is expected to be backed up directly from
`/srv/garage`, alongside the metadata snapshot copy.

## Restoring from backup

Given a restored copy of `/srv/garage` (i.e. `garage_base_dir`, covering
`garage_data_dir`) and a restored metadata snapshot (from
`/var/backups/garage/{{ garage_hostname }}-metadata`):

1. Stop garage: `systemctl stop garage`.
2. Restore `/srv/garage` to its original location, owned by the `garage`
   user, so `garage_data_dir` (bucket objects) is back in place.
3. Swap in the trusted metadata snapshot rather than trusting whatever
   `db.lmdb` came back with the raw `/srv/garage` restore (it may have been
   copied while garage was running and be inconsistent):
   ```
   mv {{ garage_metadata_dir }}/db.lmdb {{ garage_metadata_dir }}/db.lmdb.bak
   cp -r /var/backups/garage/{{ garage_hostname }}-metadata {{ garage_metadata_dir }}/db.lmdb
   chown -R garage:garage {{ garage_metadata_dir }}
   ```
4. Start garage: `systemctl start garage`.
5. Resync anything that changed between the snapshot and the outage:
   `garage -c {{ garage_config_file }} repair -a --yes tables`.

See the upstream
[Recovering from failures](https://garagehq.deuxfleurs.fr/documentation/operations/recovering/)
and
[Durability & Repairs](https://garagehq.deuxfleurs.fr/documentation/operations/durability-repairs/)
docs for the full picture (multi-node recovery, layout recovery, etc.) — this
single-node setup only ever needs the metadata-snapshot-swap path above.

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

## minio-backup bucket/key

Before running this role for the first time after pulling in the `minio-backup`
bucket support, add the two new secrets it expects:

    uv run ansible-vault edit group_vars/all/vault

Add `vault_garage_minio_backup_key_id` and `vault_garage_minio_backup_secret_key`
(e.g. `openssl rand -hex 8` / `openssl rand -hex 32`) — these become the
credentials the rclone CronJobs in `qb` authenticate to `piilo-s3.tracon.fi` with.
They're independent of `vault_garage_s3_key_id`/`_secret_key` (which stay scoped
to `cnpg-backups`), so a leaked backup-mirror credential can't be used against
the CloudNativePG bucket or vice versa.
