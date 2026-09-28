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

## Changing the replication factor

Done once, 3 to 2 on 2026-09-28, for headroom on the 900 GB volumes. Garage calls this
"technically possible but not officially supported": the layout must be deleted with the
whole cluster down and recreated under the new factor. Keys, buckets and grants live in
the metadata tables, not the layout, so they survive untouched; node identities live in
`node_key`, also untouched. Data blocks stay on disk and are rebalanced afterwards.
S3 is unavailable from the scale-down until the new layout is applied, so stop or
expect failures from uploaders (edegal's presigned uploads, the mirror CronJob).

1. Snapshot the metadata on every node and note the current state:

   ```
   kubectl -n garage exec garage-0 -- /garage meta snapshot --all
   kubectl -n garage exec garage-0 -- /garage status
   kubectl -n garage exec garage-0 -- /garage layout show
   kubectl -n garage exec garage-0 -- /garage bucket list
   kubectl -n garage exec garage-0 -- /garage key list
   ```

2. Stop the cluster: `kubectl -n garage scale statefulset garage --replicas=0` and wait for
   the pods to be gone.

3. Delete `cluster_layout` from each node's metadata volume. A throwaway pod per PVC is
   the simplest way in; the PV's node affinity places it on the right node:

   ```
   for n in 0 1 2 3; do
     kubectl -n garage run meta-reset-$n --rm -i --restart=Never --image=busybox \
       --overrides="{\"spec\":{\"containers\":[{\"name\":\"meta-reset-$n\",\"image\":\"busybox\",\"command\":[\"sh\",\"-c\",\"ls -la /mnt/meta && rm -v /mnt/meta/cluster_layout\"],\"volumeMounts\":[{\"name\":\"meta\",\"mountPath\":\"/mnt/meta\"}]}],\"volumes\":[{\"name\":\"meta\",\"persistentVolumeClaim\":{\"claimName\":\"meta-garage-$n\"}}]}}"
   done
   ```

   `db.lmdb`, `node_key` and `snapshots/` must remain; only `cluster_layout` goes.

4. Change `replicationFactor` in `values.yml`, then `helm upgrade` as in Install. The
   chart hashes its ConfigMap into a pod annotation, so this also brings the four pods
   back with the new config (`replicaCount` is 4 again). Pods stay not-ready until the
   next step.

5. Recreate the layout as in Layout bootstrap, with the same four node IDs and
   capacities, and apply it. `garage status` should list all four as healthy.

6. Confirm nothing was lost, then let rebalancing finish:

   ```
   kubectl -n garage exec garage-0 -- /garage bucket list
   kubectl -n garage exec garage-0 -- /garage key list
   kubectl -n garage exec garage-0 -- /garage stats -a        # resync queue drains to 0
   kubectl -n garage exec garage-0 -- /garage block list-errors
   uv run bin/garage_env.py garage_test -- aws s3 ls s3://garage-test/   # from the repo root
   ```

   Excess third copies are garbage-collected by the resync workers over the following
   hours; disk usage on `/mnt/big` drops accordingly.

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
