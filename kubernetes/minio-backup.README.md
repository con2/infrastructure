# minio-backup

Off-site backup mirror: continuously copies every bucket on `minio.con2.fi` into
the `minio-backup` bucket on `piilo-s3.tracon.fi` (Garage), with 90 days of
version history for anything overwritten or deleted at the source. Runs as two
Kubernetes CronJobs in this (`qb`) cluster — `minio-backup-sync` (hourly,
`rclone copy`, never deletes; a full sync currently takes ~11m) and
`minio-backup-prune` (daily, the only job allowed to delete anything, enforcing
the 90-day window). See
`infrastructure/roles/garage` for the Piilo/Garage side (bucket + key
provisioning only — Garage itself runs no backup logic, it's just the S3 target).

Full design rationale: ask whoever ran this through Claude for the plan at
`~/.claude/plans/off-site-continuous-mirroring-of-indexed-journal.md`, or see the
git history of this file.

## One-time setup

1. Create the namespace:

   ```
   kubectl create namespace minio-backup
   ```

   (No image pull secret needed — `rclone/rclone` is a public Docker Hub image.)

2. Provision a **read-only** Minio access key against `minio.con2.fi`, scoped to
   `s3:ListAllMyBuckets` + `s3:GetObject`/`s3:ListBucket` account-wide (via the
   Minio admin console or `mc admin user`/`mc admin policy` — there is no
   existing readonly-account-wide policy to reuse, since the `minio-backup/`
   repo's old service account was scoped to only its three fixed buckets, and
   `sameuser`/`harbor` policies in this directory are unrelated to Minio's own
   IAM). Note the resulting access key ID and secret.

3. Fetch the destination Garage key created by the `garage` Ansible role's
   `minio-backup` bucket support (`infrastructure/roles/garage`) — run this from
   `infrastructure/`, after applying that role to `piilo`:

   ```
   uv run ansible-vault view group_vars/all/vault | \
     uv run python3 -c "import sys, yaml; d = yaml.safe_load(sys.stdin); \
     print(d['vault_garage_minio_backup_key_id']); print(d['vault_garage_minio_backup_secret_key'])"
   ```

   (Piping straight into the extractor avoids ever displaying the rest of the
   vault's contents on screen.)

4. Create the credentials Secret (never commit these values):

   ```
   kubectl create secret generic minio-backup-rclone-credentials \
     -n minio-backup \
     --from-literal=RCLONE_CONFIG_MINIO_BACKUP_SRC_ACCESS_KEY_ID=<minio readonly key id> \
     --from-literal=RCLONE_CONFIG_MINIO_BACKUP_SRC_SECRET_ACCESS_KEY=<minio readonly secret> \
     --from-literal=RCLONE_CONFIG_MINIO_BACKUP_DST_ACCESS_KEY_ID=<garage minio-backup key id> \
     --from-literal=RCLONE_CONFIG_MINIO_BACKUP_DST_SECRET_ACCESS_KEY=<garage minio-backup secret>
   ```

5. Apply the config and CronJobs:
   ```
   kubectl apply -f minio-backup.rclone-config.configmap.yaml
   kubectl apply -f minio-backup.cronjob-sync.yaml
   kubectl apply -f minio-backup.cronjob-prune.yaml
   ```

## Testing

Trigger a manual run instead of waiting for the schedule:

```
kubectl create job --from=cronjob/minio-backup-sync minio-backup-sync-manual -n minio-backup
kubectl logs -n minio-backup -l job-name=minio-backup-sync-manual --follow
```

Same pattern with `minio-backup-prune` to test retention.

Rehearse against `garagefs-playground/`'s in-cluster Garage first if you want to
validate changes to these manifests without touching production `piilo-s3`.

## Operating

- `kubectl get cronjob -n minio-backup` shows `lastScheduleTime`/
  `lastSuccessfulTime` for both jobs.
- A leaked `MINIO_BACKUP_DST` credential could delete backup data directly on
  Garage (its `bucket allow` model has no write-without-delete option) — the
  external BackupPC-style nightly backup of `/srv` on `piilo` (see
  `infrastructure/roles/prebackup`) is the fallback recovery path for that
  scenario, independent of anything in this namespace.
