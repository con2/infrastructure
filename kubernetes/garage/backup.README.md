# garage-backup

Off-site copy of buckets on `garage.con2.fi` (the cluster's Garage, see `README.md`) into
the `garage-backup` bucket on `piilo-s3.tracon.fi`, with 90 days of version history for anything
overwritten or deleted at the source. Edegal site buckets (`larppikuvat`, `conikuvat`) contribute
only their `pictures/` prefix: previews, thumbnails and in-flight uploads are not copied, since the
media worker regenerates the former from the originals and the latter are transient. Kompassi's
buckets (`kompassidev` and `kompassi`) are copied whole. Layout on piilo: `garage-backup/<bucket>/current/`
and `garage-backup/<bucket>/versions/<timestamp>/`. Two CronJobs in namespace `garage-backup`:
`garage-backup-sync` (hourly, `rclone copy`, never deletes) and `garage-backup-prune` (daily, the
only job allowed to delete, enforcing the 90-day window).

Originals that still live on the NFS export (all legacy content until stage 2 of con2/edegal#245
moves them into Garage) are outside this job. Once they are migrated, this copy covers them too.

Sizing: the mirror went live on 2026-09-28 while the edegal site buckets were still nearly empty
(their 837 GB of originals are on the NFS export until the picture migration), so the first copy
was small and quick. Once the pictures move, the piilo bucket needs about 1 TB with headroom for
growth and versions, and that first post-migration sync must be run by hand (step 6). Adding a
bucket means a line in both CronJobs, a `bucket allow --read` for the reader key, and a decision
whether to copy it whole or only a prefix.

## One-time setup

1. Create the namespace:

   ```
   kubectl create namespace garage-backup
   ```

2. Create a **read-only** key on the cluster's Garage and grant it read on every site bucket. Garage
   grants read without write, so nothing in this namespace can ever modify production media:

   ```
   kubectl -n garage exec garage-0 -- /garage key create garage-backup-reader   # prints key ID and secret
   kubectl -n garage exec garage-0 -- /garage bucket allow --read larppikuvat --key garage-backup-reader
   kubectl -n garage exec garage-0 -- /garage bucket allow --read conikuvat --key garage-backup-reader
   kubectl -n garage exec garage-0 -- /garage bucket allow --read kompassidev --key garage-backup-reader
   kubectl -n garage exec garage-0 -- /garage bucket allow --read kompassi --key garage-backup-reader
   ```

3. Fetch the destination key created by the `garage` Ansible role's `garage-backup` bucket support
   (`infrastructure/roles/garage`), after applying that role to `piilo`:

   ```
   uv run bin/garage_env.py garage_backup -- env | grep ^AWS_
   ```

4. Create the credentials Secret (never commit these values):

   ```
   kubectl create secret generic garage-backup-rclone-credentials \
     -n garage-backup \
     --from-literal=RCLONE_CONFIG_GARAGE_BACKUP_SRC_ACCESS_KEY_ID=<garage-backup-reader key id> \
     --from-literal=RCLONE_CONFIG_GARAGE_BACKUP_SRC_SECRET_ACCESS_KEY=<garage-backup-reader secret> \
     --from-literal=RCLONE_CONFIG_GARAGE_BACKUP_DST_ACCESS_KEY_ID=<piilo garage-backup key id> \
     --from-literal=RCLONE_CONFIG_GARAGE_BACKUP_DST_SECRET_ACCESS_KEY=<piilo garage-backup secret>
   ```

5. Apply the config and CronJobs:

   ```
   kubectl apply -f backup.rclone-config.configmap.yaml
   kubectl apply -f backup.cronjob-sync.yaml
   kubectl apply -f backup.cronjob-prune.yaml
   ```

   The sync CronJob is live as committed. That was fine on 2026-09-28 because the source was
   small; the first copy ran within the scheduled deadline.

6. Before a bulk arrival at the source (the edegal picture migration, hundreds of GB), suspend
   the schedule, run one copy by hand without the deadline, then unsuspend and check the next two
   scheduled runs against `activeDeadlineSeconds` in the sync manifest:

   ```
   kubectl -n garage-backup patch cronjob garage-backup-sync -p '{"spec":{"suspend":true}}'
   kubectl -n garage-backup create job --from=cronjob/garage-backup-sync garage-backup-initial \
     --dry-run=client -o yaml | sed '/activeDeadlineSeconds/d' | kubectl apply -f -
   kubectl -n garage-backup logs job/garage-backup-initial --follow
   kubectl -n garage-backup patch cronjob garage-backup-sync -p '{"spec":{"suspend":false}}'
   ```

   A scheduled run that starts on a source that big is killed by the deadline long before it
   finishes, and `rclone copy` resumes where it left off, so a forgotten suspend costs time, not
   data.

## Testing

Trigger a manual run instead of waiting for the schedule:

```
kubectl -n garage-backup create job --from=cronjob/garage-backup-sync garage-backup-sync-manual
kubectl -n garage-backup logs -l job-name=garage-backup-sync-manual --follow
```

Same pattern with `garage-backup-prune` to test retention.

Checks worth doing after the first runs, with `uv run bin/garage_env.py garage_backup` for the
destination side and the reader key for the source side:

- `rclone check --one-way garage_backup_src:larppikuvat/pictures garage_backup_dst:garage-backup/larppikuvat/current/pictures`
  reports no missing files.
- Upload a photo on the site: after the next run its `pictures/` object is in `current/` and its
  previews are not.
- Delete that photo: after the next run the original sits under `versions/<timestamp>/`.
- The reader key cannot write: `aws s3 cp` with it into `larppikuvat` returns 403.

## Restoring

Storage keys are preserved, so a restored object is found by the unchanged `v4_media` row. With a
key that may write to the site bucket (never the reader key):

```
rclone copy garage_backup_dst:garage-backup/<site>/current/pictures/<path> garage_src_rw:<site>/pictures/<path>
```

For a photo deleted at the source, look for it under `versions/<timestamp>/pictures/` instead.
Previews and thumbnails are regenerated by queueing a media job for the photo (`v4_media_job`).

## Operating

- `kubectl -n garage-backup get cronjob` shows `lastScheduleTime`/`lastSuccessfulTime` for both jobs.
- A leaked destination credential could delete backup data directly on piilo (Garage's
  `bucket allow` has no write-without-delete option); the external nightly backup of `/srv` on
  `piilo` (`infrastructure/roles/prebackup`) is the fallback for that scenario.
