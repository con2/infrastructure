# cloudnative-pg

In-cluster PostgreSQL for qb, run by the [CloudNativePG](https://cloudnative-pg.io/) operator.
One shared Cluster named `postgres` (three instances, PostgreSQL 18, one per node) in namespace
`postgres`, backed up continuously to the `cnpg-backups` bucket on `piilo-s3.tracon.fi` through
the [Barman Cloud plugin](https://cloudnative-pg.io/plugin-barman-cloud/). It replaces the
bare-metal `siilo.tracon.fi` server (Ansible role `postgresql`, Barman on `piilo`), one app at a
time.

Files, all in this directory (`infrastructure/kubernetes/postgres`; the commands below assume it is the working directory unless they say otherwise):

- `cloudnative-pg.values.yml`: operator Helm values.
- `plugin-barman-cloud.values.yml`: plugin Helm values.
- `objectstore.yaml`: the piilo-s3 backup target.
- `cluster.yaml`: the Cluster.
- `scheduledbackup.yaml`: nightly base backup.
- `create-app-database.sh`: one command per app, creates its role and database.
- `migrate-database.sh`: copies an app's database from siilo into the cluster in a one-off pod.
- `update-secret.sh`: writes the credentials into the Secret an app reads.
- `secret-shape.sh`: shared by the two scripts above; how they recognise an app's Secret.

Per-app `DatabaseRole`/`Database` objects are **not** kept in this repository. The
create-app-database script applies them and the Kubernetes API is the only record of which apps
have a database: `kubectl -n postgres get databaserole,database`.

## Versions

| Component | Version | Where pinned |
|---|---|---|
| CloudNativePG operator | 1.30.1 | chart `cnpg/cloudnative-pg` 0.29.1 |
| Barman Cloud plugin | v0.15.0 | chart `cnpg/plugin-barman-cloud` 0.8.0 |
| PostgreSQL image | `ghcr.io/cloudnative-pg/postgresql:18.4-standard-trixie` | `cluster.yaml` |

In-tree Barman Cloud support (`spec.backup.barmanObjectStore`) is deprecated and disappears in
CloudNativePG 1.31; everything here uses the plugin from the start.

## One-time installation

The operator and plugin go into `cnpg-system`, not a namespace named after the release: the
plugin has to live in the operator's namespace and its documentation assumes `cnpg-system`. The
plugin needs cert-manager, which qb already runs.

```sh
helm repo add cnpg https://cloudnative-pg.github.io/charts
helm repo update cnpg
helm upgrade --install cloudnative-pg cnpg/cloudnative-pg -n cnpg-system --create-namespace \
  --version 0.29.1 -f cloudnative-pg.values.yml --wait
helm upgrade --install plugin-barman-cloud cnpg/plugin-barman-cloud -n cnpg-system \
  --version 0.8.0 -f plugin-barman-cloud.values.yml --wait
kubectl -n cnpg-system get pods
```

The database images are public, so the namespace needs no image pull secret and
`../create-namespace.sh` is not used:

```sh
kubectl create namespace postgres
```

Fetch the piilo-s3 key from the Ansible vault (profile `cnpg_backup` maps to
`vault_garage_s3_key_id` / `vault_garage_s3_secret_key`) and create the Secret the ObjectStore
reads. `garage_env.py` runs from the repository root. Never commit these values:

```sh
(cd ../.. && uv run bin/garage_env.py cnpg_backup -- env | grep ^AWS_)
kubectl -n postgres create secret generic cnpg-backups-s3 \
  --from-literal=ACCESS_KEY_ID=<AWS_ACCESS_KEY_ID> \
  --from-literal=ACCESS_SECRET_KEY=<AWS_SECRET_ACCESS_KEY> \
  --from-literal=REGION=garage
```

Before applying the Cluster, check the nodes can take three pods that each request 2 GiB of
memory and 500m CPU (`kubectl describe nodes | grep -A6 Allocated`). Then:

```sh
kubectl apply -f objectstore.yaml
kubectl apply -f cluster.yaml
kubectl -n postgres get cluster postgres -w     # until "Cluster in healthy state"
kubectl -n postgres get pods -o wide            # three instances on three nodes
kubectl apply -f scheduledbackup.yaml  # immediate: true takes the first backup now
```

Install the `kubectl cnpg` plugin locally (`brew install kubectl-cnpg`), then confirm archiving
and the first base backup:

```sh
kubectl cnpg status -n postgres postgres
kubectl -n postgres get backup
(cd ../.. && uv run bin/garage_env.py cnpg_backup -- aws s3 ls s3://cnpg-backups/postgres/ --recursive | tail)
```

`Continuous Backup status` must say archiving is working and the listing must show both
`base/` and `wals/` under `cnpg-backups/postgres/`. Do this before anything depends on the
cluster: it is the only proof that Garage accepts Barman's requests.

## Giving an app a database

One command per app. It creates the password Secret `<app>-db-credentials` in namespace
`postgres` (a hex password, so it can be pasted into a URL unescaped; an existing Secret is kept,
so re-running never rotates anything), labels it `cnpg.io/reload=true`, applies a `DatabaseRole`
and a `Database` of the same name owned by that role, and waits for `status.applied: true`.

```sh
./create-app-database.sh larpit
```

Every database is created Finnish on ICU (`fi-FI`, libc `fi_FI.UTF-8`, UTF8). The cluster's
`initdb` sets the same, so `template1` matches, but the script spells it out per database so it
holds even if the template is ever changed.

Then hand the credentials to the app. Our apps keep database settings in a Secret in one of two
shapes, and the second command detects which:

- Django apps: keys `hostname`, `database`, `username`, `password`, exactly these and lower
  case.
- Node apps: key `DATABASE_URL`. These also get `DATABASE_URL_REPLICA`, pointing at
  `postgres-ro`; an app that does not read it ignores the extra variable.

```sh
./update-secret.sh larpit larpit-production larpit
kubectl -n larpit-production rollout restart deploy/node
```

Only the database keys are written; other keys in the Secret stay. A Secret matching neither
shape is left untouched and the script lists its keys, pointing out near misses such as
`POSTGRES_PASSWORD` or `Hostname`. Fix the app's chart to use the exact keys, then rerun.

What the app ends up with:

```
hostname: postgres-rw.postgres.svc.cluster.local   (Django)
postgresql://<app>:<password>@postgres-rw.postgres.svc.cluster.local:5432/<app>?sslmode=disable   (Node, DATABASE_URL)
postgresql://<app>:<password>@postgres-ro.postgres.svc.cluster.local:5432/<app>?sslmode=disable   (Node, DATABASE_URL_REPLICA)
```

`postgres-rw` always points at the current primary and follows failovers. `postgres-ro` load
balances over the replicas only, so reads there may trail the primary by replication lag and
fail if no replica is up (rolling updates restart one instance at a time, so that takes two
instances down at once). larpit-fi is the first app to use it, for its public pages and API.

TLS is off inside the cluster on purpose. CloudNativePG issues its own CA and rotates it, so a
copy of its `ca.crt` in the app's namespace would go stale on rotation and there is no
secret-sync tool on qb to keep it fresh. Traffic never leaves the pod network. The default
`pg_hba` ends in `host all all all scram-sha-256`, so plain connections authenticate with the
role's password. Django apps that add `?sslmode=require` through `POSTGRES_EXTRAS` or settings
must drop it; the update script does not touch that. Revisit if a secret reflector is ever
installed.

Rotating a password is editing `<app>-db-credentials` in `postgres` (the operator applies it
because of the reload label) and running update-secret again.

To remove an app's database, delete the `Database` and `DatabaseRole` objects. Both carry
`ReclaimPolicy: retain`, so the PostgreSQL database and role stay behind for a superuser to drop
by hand (`kubectl cnpg psql -n postgres postgres`).

## Migrating an app off siilo

Recipe used for the pilot, `larpit-fi` (chart in `larpit-fi/chart`, Secret `larpit` in namespace
`larpit-production`). Every other siilo tenant follows the same steps with its own names.

1. `./create-app-database.sh larpit`. The password is in
   `postgres/larpit-db-credentials`.
2. Announce a short outage. Stop everything that writes:
   `kubectl -n larpit-production scale deploy/node --replicas=0` and
   `kubectl -n larpit-production patch cronjob sync-larppikuvat -p '{"spec":{"suspend":true}}'`.
3. `./migrate-database.sh larpit larpit-production larpit`. It reads the *old* credentials
   from the app's Secret (either shape), confirms the app is stopped, and runs `pg_dump |
   pg_restore` in a one-off pod in `postgres` using the cluster's own image, so `pg_dump` is at
   least as new as either server. The pod refuses a destination that already has tables, so a
   rerun never restores on top of data. It prints per-table row counts from both sides at the
   end; they should match. Details worth knowing:
   - qb's address range is already in siilo's `postgresql_access_networks` and siilo serves a
     Let's Encrypt certificate, so the source connection uses `sslmode=verify-full`.
   - The dump is taken with `--no-owner --no-acl` and restored as the app's own role, which
     therefore owns every object. `pg_restore -C` is deliberately not used: it would recreate
     the database with siilo's locale instead of the Finnish ICU one from step 1.
   - Any migration-marker tables the app's ORM keeps are ordinary data and come along.
   - The connection strings ride in a Secret named after the pod for the duration of the run,
     not on the pod's command line.
4. `./update-secret.sh larpit larpit-production larpit`, scale back up,
   unsuspend the CronJob, and watch the migration init container and the health endpoint.
5. After a few days of stability, take a manual backup (`kubectl cnpg backup -n postgres postgres
   --method=plugin --plugin-name=barman-cloud.cloudnative-pg.io`), then drop the database and
   role on siilo. Once nothing is left on siilo, decommissioning it and the Barman host is a
   separate task.

## Backups

- WAL archiving is continuous; `postgres-daily` takes a base backup at 03:30 UTC. Both go to
  `s3://cnpg-backups/postgres/` on piilo-s3, compressed with gzip.
- Retention is 30 days, enforced by the plugin sidecar. Older base backups and the WALs that
  only they need are deleted; point-in-time recovery reaches back 30 days.
- The bucket key has `--write`, which in Garage implies delete. A leaked key could wipe the
  backups; the nightly external backup of `/srv` on piilo is the fallback (see the `garage`
  role's README).
- Check: `kubectl cnpg status -n postgres postgres` (last archived WAL, first and last backup),
  `kubectl -n postgres get backup`, and the S3 listing shown under installation.
- One-off backup: `kubectl cnpg backup -n postgres postgres --method=plugin
  --plugin-name=barman-cloud.cloudnative-pg.io`.

## Restore drill

Run this before the first app migrates, and again once a year. It stands up a throwaway
cluster from the latest backup, next to production, without touching production.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-restore-test
  namespace: postgres
spec:
  imageName: ghcr.io/cloudnative-pg/postgresql:18.4-standard-trixie
  instances: 1
  storage:
    size: 20Gi
    storageClass: local-path
  bootstrap:
    recovery:
      source: production
      # For point-in-time recovery add:
      # recoveryTarget:
      #   targetTime: "2026-09-28 06:00:00+00"
  externalClusters:
    - name: production
      plugin:
        name: barman-cloud.cloudnative-pg.io
        parameters:
          barmanObjectName: piilo-s3
          serverName: postgres
```

The test cluster has no `spec.plugins` entry of its own on purpose: with one, it would start
archiving its WALs into the production path under the same `serverName`. Never give a restored
cluster the production `serverName` as its own archive target.

```sh
kubectl apply -f restore-test.yaml
kubectl -n postgres get cluster postgres-restore-test -w
kubectl cnpg psql -n postgres postgres-restore-test -- -c '\l'
kubectl cnpg psql -n postgres postgres-restore-test -- -d larpit -c 'select count(*) from larp'
kubectl -n postgres delete cluster postgres-restore-test
```

Restoring production for real is the same manifest with the production name after the broken
cluster has been deleted, which is why the drill matters.

## Failover and node loss

- Killing the primary pod promotes a replica within seconds and `postgres-rw` follows. Try it:
  `kubectl -n postgres delete pod postgres-1` (whichever `kubectl cnpg status` marks primary).
- Manual switchover: `kubectl cnpg promote -n postgres postgres postgres-2`.
- `local-path` volumes are pinned to a node. If a node dies, the operator fails over to a
  replica, but the instance that lived on the dead node stays `Pending` forever because its PVC
  can only be mounted there. To rebuild it on another node, delete that instance's PVC and Pod
  (`kubectl -n postgres delete pvc postgres-3 && kubectl -n postgres delete pod postgres-3`);
  the operator re-clones it from the primary. Do this only after confirming a new primary is
  serving.
- Instance pods are annotated for Alloy's pod scraping (port 9187, `cnpg_*` metrics), so
  `cnpg_collector_up` shows all three instances.

## Upgrades

- Operator: bump `--version` in the Helm command; the operator restarts instance pods in a
  rolling fashion when the instance manager changes.
- PostgreSQL minor: change the image tag in `cluster.yaml` and apply; replicas restart
  first, then a switchover.
- PostgreSQL major: same file, and the operator performs an in-place `pg_upgrade` of the
  primary with the cluster stopped. Take a manual backup first.
