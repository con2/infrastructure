# garage

[Garage](https://garagehq.deuxfleurs.fr/) is the S3-compatible object store replacing
Minio (`minio.con2.fi`, a 2020-era release with no upgrade path since MinIO discontinued
the community edition). Four nodes, one per `qb` host, replication factor 2 (3 until
2026-09-28), public endpoint `https://garage.con2.fi`. The install was rehearsed from scratch in
`Hobby/garagefs-playground/`, whose Taskfile tasks (`garage:install`, `garage:layout:*`,
`garage:key:create`, `garage:bucket:*`) work unchanged against production with
`KUBECONFIG` exported.

Migrating Minio's buckets and re-pointing apps is not covered here.

## Install

The chart is not in any Helm repository index. Clone the Garage repository at the
pinned tag and install from the in-tree chart path. The chart's `appVersion` matches
the tag, so this also picks the image version.

```
git clone --branch v2.4.1 --depth 1 https://git.deuxfleurs.fr/Deuxfleurs/garage.git /tmp/garage-v2.4.1
helm upgrade --install garage /tmp/garage-v2.4.1/script/helm/garage \
  -n garage --create-namespace -f values.yml --wait --timeout 5m
kubectl -n garage rollout status statefulset/garage
```

Then check placement: 8 PVCs `Bound`, `meta-*` on `local-path`, `data-*` on
`local-path-big`, one pod per node.

```
kubectl -n garage get pvc
kubectl -n garage get pod -o wide
```

Pods stay `0/1 Ready` until the layout below is applied; that is expected. Two things
bit the first install (2026-09-26):

- The `local-path-big` provisioner runs a single helper pod with a fixed name, so
  provisioning four PVCs at once races. One data directory was created by the kubelet
  (root-owned 0755) instead of the helper (0777), and that pod crashed with
  `Permission denied` on startup. Fix: `chmod 0777` the empty directory on the node
  (a throwaway busybox pod with a `hostPath` mount of `/mnt/big/localpath` works;
  there is no `ls` in the Garage image).
- `deployment.podManagementPolicy` is immutable on a StatefulSet. Changing it means
  `kubectl -n garage delete statefulset garage` (PVCs survive) and re-running the
  install; node identities live in the `meta` PVCs, so nodes keep their IDs.

## Layout bootstrap (one time)

The chart never touches the cluster layout. Pods are `Ready` before a layout exists
(readiness is the admin API's `/health`), but S3 requests fail until it is applied.

```
kubectl -n garage exec garage-0 -- /garage status            # lists 4 node IDs
kubectl -n garage exec garage-0 -- /garage layout assign -z qb -c 900G <id1>
kubectl -n garage exec garage-0 -- /garage layout assign -z qb -c 900G <id2>
kubectl -n garage exec garage-0 -- /garage layout assign -z qb -c 900G <id3>
kubectl -n garage exec garage-0 -- /garage layout assign -z qb -c 900G <id4>
kubectl -n garage exec garage-0 -- /garage layout show        # prints "Current cluster layout version: N"
kubectl -n garage exec garage-0 -- /garage layout apply --version N+1
```

All nodes are in one site, so a single zone `qb`; Garage spreads the replicas across
distinct nodes within the zone. Capacity is a relative weight, equal on all four.

## Rebuilding the cluster (keys and buckets preserved)

Done once, on 2026-09-28, to go from replication factor 3 to 2 while the buckets were still
small. Garage cannot change the factor in place in a supported way, so the cluster is torn
down and rebuilt, and the data comes back from the piilo mirror. Keys keep their id and
secret through `key import`, so no vault or application Secret changes; only the
`garage-rpc-secret` is new, which is invisible to clients. S3 is down from step 3 until
step 7, so stop or expect failures from uploaders (edegal's presigned uploads, the mirror
CronJob).

1. Make sure the mirror is current: run `garage-backup-sync` by hand (see
   `backup.README.md`, Testing) and wait for it to finish. Then suspend it:

   ```
   kubectl -n garage-backup patch cronjob garage-backup-sync -p '{"spec":{"suspend":true}}'
   ```

2. Export every key with its secret, and every bucket's grants. Keep the output somewhere
   private until step 6 is done:

   ```
   for k in $(kubectl -n garage exec garage-0 -- /garage key list | awk 'NR>1 {print $2}'); do
     kubectl -n garage exec garage-0 -- /garage key info --show-secret $k
   done
   for b in $(kubectl -n garage exec garage-0 -- /garage bucket list | awk 'NR>1 {print $1}'); do
     kubectl -n garage exec garage-0 -- /garage bucket info $b
   done
   ```

3. Tear down. PVC deletion runs the provisioner's `rm -rf` helper on every node, which is
   the point here:

   ```
   helm -n garage uninstall garage
   kubectl -n garage delete pvc --all
   kubectl -n garage get pvc,pv,pod        # nothing left
   ```

4. Install again as in Install with the new `values.yml`, then Layout bootstrap. The node
   IDs are new (`node_key` went with the volumes); take them from `garage status`.

5. Recreate the buckets and re-import the keys under their old ids and secrets, then the
   grants from step 2:

   ```
   kubectl -n garage exec garage-0 -- /garage bucket create <bucket>
   kubectl -n garage exec garage-0 -- /garage key import <key id> <secret> -n <name> --yes
   kubectl -n garage exec garage-0 -- /garage bucket allow --read [--write] [--owner] <bucket> --key <name>
   ```

   Per-bucket settings that are not in `bucket info` have to be redone by their owners:
   edegal's CORS rules come back with `npm run s3:setup` per site (edegal `chart/README.md`).

6. Restore the data with a temporary write key and a one-off rclone Job in `garage-backup`,
   reusing the CronJob's ConfigMap. The mirror holds `pictures/` of the edegal buckets under
   `garage-backup/<site>/current/pictures` and whole buckets otherwise:

   ```
   kubectl -n garage exec garage-0 -- /garage key create restore        # note id and secret
   for b in larppikuvat conikuvat kompassidev; do
     kubectl -n garage exec garage-0 -- /garage bucket allow --read --write $b --key restore
   done
   kubectl -n garage-backup create secret generic garage-restore-credentials \
     --from-literal=RCLONE_CONFIG_GARAGE_BACKUP_SRC_ACCESS_KEY_ID=<restore key id> \
     --from-literal=RCLONE_CONFIG_GARAGE_BACKUP_SRC_SECRET_ACCESS_KEY=<restore secret> \
     --from-literal=RCLONE_CONFIG_GARAGE_BACKUP_DST_ACCESS_KEY_ID=<piilo garage-backup key id> \
     --from-literal=RCLONE_CONFIG_GARAGE_BACKUP_DST_SECRET_ACCESS_KEY=<piilo garage-backup secret>
   kubectl -n garage-backup create job --from=cronjob/garage-backup-sync garage-restore \
     --dry-run=client -o yaml \
     | sed -e 's/garage-backup-rclone-credentials/garage-restore-credentials/' -e '/activeDeadlineSeconds/d' \
     > /tmp/garage-restore.yaml
   ```

   Edit `/tmp/garage-restore.yaml`: replace the container's script with the reverse copies,
   then apply and follow it:

   ```
   rclone copy garage_backup_dst:garage-backup/larppikuvat/current/pictures garage_backup_src:larppikuvat/pictures --fast-list --transfers 4
   rclone copy garage_backup_dst:garage-backup/conikuvat/current/pictures   garage_backup_src:conikuvat/pictures   --fast-list --transfers 4
   rclone copy garage_backup_dst:garage-backup/kompassidev/current          garage_backup_src:kompassidev          --fast-list --transfers 4
   ```

   Previews and thumbnails were never mirrored; edegal regenerates them from the originals
   (`npm run media:backfill` in the edegal repo queues the work). Afterwards:

   ```
   kubectl -n garage exec garage-0 -- /garage key delete --yes <restore key id>
   kubectl -n garage-backup delete secret garage-restore-credentials job garage-restore
   ```

7. Verify and resume: bucket and key lists match step 2, `aws s3 ls` with an app key works,
   the sites serve images, then unsuspend the mirror. Its next run finds the destination
   already current and copies nothing.

   ```
   kubectl -n garage-backup patch cronjob garage-backup-sync -p '{"spec":{"suspend":false}}'
   ```

## Public endpoint

```
kubectl apply -f gateway.yaml
kubectl -n garage get certificate,gateway
```

Wait for the `Certificate` to be `Ready` and the `Gateway` to be `Programmed`. The
manifest is a Gateway API `Gateway` plus `HTTPRoute`s, not an `Ingress`, matching
edegal v4 and larpit-fi. There is no body-size cap on the route, and
`traefik.values.yml` disables the entrypoint `readTimeout` so uploads longer than 60
seconds are not cut off.

## Keys and buckets

Garage has no IAM policies. Each app gets its own key and a per-bucket grant.

```
kubectl -n garage exec garage-0 -- /garage key create <name>        # prints key ID and secret
kubectl -n garage exec garage-0 -- /garage bucket create <bucket>
kubectl -n garage exec garage-0 -- /garage bucket allow --read --write [--owner] <bucket> --key <name>
```

`--write` implies delete; there is no write-without-delete grant.

## Client configuration

- Endpoint: `https://garage.con2.fi`
- Region: `garage`
- Path-style addressing forced (AWS CLI: `aws configure set default.s3.addressing_style path`,
  or set `s3.addressing_style = path` in the profile). Virtual-hosted style needs a
  wildcard DNS record that does not exist.

## Secrets

`rpc_secret` lives in Secret `garage-rpc-secret`, generated by the chart on first
install and preserved across `helm upgrade`. Back it up alongside the metadata
snapshots; if it is lost, every node must be reconfigured together.

## Where data lives

- Metadata (LMDB plus snapshots under `snapshots/`):
  `/var/lib/rancher/k3s/storage/pvc-*_garage_meta-garage-N` on each node
- Data blocks: `/mnt/big/localpath/pvc-*_garage_data-garage-N`

Never delete the PVCs to "restart" a node: PVC deletion runs the provisioner's `rm -rf`
helper. After first scheduling each PV carries node affinity, so `garage-N` is
permanently bound to one node. A dead node means that replica is gone until the node
is rebuilt and the PVC/PV recreated; the other replica keeps data readable, and writes
to partitions the dead node holds fail until it is back (replication factor 2 with
`consistent` mode needs both copies).

## Operating

```
kubectl -n garage exec garage-0 -- /garage status                # all four Healthy
kubectl -n garage exec garage-0 -- /garage stats
kubectl -n garage exec garage-0 -- /garage block list-errors     # should be empty
```

Metrics are on each pod's admin port 3903 at `/metrics`; the pod annotations in
`values.yml` make Alloy scrape them.
