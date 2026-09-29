# The qb cluster

**qb** is the Kubernetes cluster that hosts the Tracon and Con2 services: kompassi.eu, larpit.fi,
larppikuvat.fi, conikuvat.fi and friends. Four Ubuntu VMs (`qb1`..`qb4`, `*.con2.fi`), each with
an SSD for the OS and fast storage and a spinning disk mounted at `/mnt/big`.

| Concern | What runs | Files here |
|---|---|---|
| Kubernetes | [k3s](https://k3s.io), three servers (`qb1`..`qb3`) and one agent (`qb4`), upgraded by the system-upgrade-controller from the k3s stable channel | `system-upgrade.plans.yaml` |
| Ingress | [Traefik](https://traefik.io/) as a hostNetwork DaemonSet on every node, serving both `Ingress` and Gateway API (`Gateway`/`HTTPRoute`) | `traefik.values.yml`, `traefik-middlewares.yaml` |
| TLS | [cert-manager](https://cert-manager.io/) with a Let's Encrypt HTTP-01 `ClusterIssuer` | `cert-manager.values.yml`, `letsencrypt-prod.clusterissuer.yaml` |
| Storage | k3s's built-in `local-path` class on the SSD (the default) and a second local-path provisioner, `local-path-big`, on `/mnt/big`. Both are node-local; neither enforces size | `local-path-provisioner.values.yaml` |
| PostgreSQL | [CloudNativePG](https://cloudnative-pg.io/): one shared three-instance cluster, backed up to piilo-s3 | [`postgres/`](postgres/README.md) |
| Object storage | [Garage](https://garagehq.deuxfleurs.fr/) at garage.con2.fi, four nodes, replication factor 3, mirrored off-site by rclone CronJobs | [`garage/`](garage/README.md) |
| Redis | `redis-ha` chart (Redis + HAProxy), used by kompassi and the emskaffolden-deployed Django apps | `redis-ha.values.yml` |
| CI runners | GitHub Actions Runner Controller with one runner scale set for the `con2` org | `actions-runner-controller.yml`, `actions-runner-scaleset.*` |
| Observability | Grafana Alloy on the nodes ships logs and pod metrics to the external Loki/Prometheus at qb-stalker.con2.fi. Alloy scrapes pods by `prometheus.io/scrape` annotations, not `ServiceMonitor`s; there is no Prometheus Operator here | (managed outside this repo) |

Off-site backups land on `piilo-s3.tracon.fi`, a single-node Garage outside the cluster provisioned
by the Ansible role `roles/garage` (see [`../docs/2026-06-24-piilo-garage-for-cloudnativepg.md`](../docs/2026-06-24-piilo-garage-for-cloudnativepg.md)).

## No longer here

Removed in 2026, values files deleted in commit `4faadc3`; git history has them if ever needed:
Longhorn (storage is node-local now), Minio (replaced by Garage, its off-site mirror CronJobs
went with it), Harbor (images come from ghcr.io), Concourse, Sentry, the in-cluster Loki/Grafana
stack (logs go to qb-stalker), ingress-nginx (Traefik since 2026-08-03) and
kubernetes-secret-generator. The `redmine` release (pora.tracon.fi) still exists but is scaled
to zero and on a siilo database; `redmine.values.yaml` stays with it.

TODO:

* [ ] Automate Helm chart installations (Ansible? an in-cluster controller?). Today every install
  and upgrade is a `helm` command run by hand from this directory.
* [ ] Move the remaining databases off `siilo.tracon.fi` into the CloudNativePG cluster, one app at
  a time with the scripts in [`postgres/`](postgres/README.md), then decommission siilo and Barman.
* [ ] Convert the remaining `Ingress` apps to Gateway API (one `Gateway` per app namespace; edegal v4
  and larpit-fi are done) and drop cert-manager `Certificate` objects from app charts in favour of
  cert-manager's Gateway support.

## Conventions

* **Values**: every Helm release's values file lives in this directory as `<release>.values.yml`,
  without secrets. Plain manifests are `<app>.<kind>.yaml`. An app with many files gets a
  subdirectory (`postgres/`, `garage/`).
* **Release name**: the same as the chart/application name.
* **Namespace**: the same as the release name, with the exceptions noted per service below
  (`cnpg-system`, `system-upgrade`, `arc-systems`/`arc-runners`).
* **Runbooks**: anything with more than an install command has its own `<app>.README.md`.
* Any `kubectl patch` or edit against a Helm-managed object must be back-ported into the values
  file before the next `helm upgrade`, or the upgrade silently reverts it. This caused a real
  cluster-wide outage once (an admission webhook fix on ingress-nginx).

## Access

qb nodes only have HTTP/HTTPS open to the world. SSH hops through `monokkeli` (see `../ssh-config`):

    Host qb1
        Hostname qb1.con2.fi
        ProxyJump monokkeli

k3s hardcodes `/etc/rancher/k3s/k3s.yaml` as its kubeconfig on the nodes. For a workstation, copy
that file, point `KUBECONFIG` at it, and tunnel the API:

    ssh -fNL 6443:localhost:6443 qb1

## Node provisioning

The Ansible side (`../qb.yml`, roles `k3s-base`, `k3s-storage`, `k3s-initial-server`, `k3s-server`,
`k3s-agent`) dates from the cluster's creation and is stale in places: `group_vars/k3s` still
names k3s v1.19, and `k3s-storage` still mounts Longhorn paths. It is not used for day-to-day
operation. What it documents that still holds: `/dev/sdc1` (SSD) at `/var/lib/rancher`, `/dev/sdb1`
(spinning) at `/mnt/big`, both XFS; the join token lives in `/var/lib/rancher/k3s/server/token` on
`qb1`. Read the roles before trusting them for a new node.

k3s itself is upgraded by the [system-upgrade-controller](https://github.com/rancher/system-upgrade-controller)
following the stable channel; the two `Plan`s (servers first, then the agent) are in
`system-upgrade.plans.yaml`, namespace `system-upgrade`.

## Cluster services

Install order for a rebuild: Gateway API CRDs, then Traefik, cert-manager and the `ClusterIssuer`,
then local-path-provisioner, then everything else in any order. Each service's own README covers
its details; this lists the install commands.

### Traefik

Traefik runs as a DaemonSet with `hostNetwork: true` binding hostPort 80/443 on all four nodes
(not k3s's bundled Traefik, which was disabled at bootstrap). `traefik.values.yml` carries the
hard-won settings: `service.spec.type: ClusterIP` (otherwise k3s's ServiceLB deploys a second
hostPort-binding DaemonSet), metrics on 9101 (node-exporter owns 9100), running as root with
capabilities kept (non-root + `NET_BIND_SERVICE` failed for this image), and
`respondingTimeouts.readTimeout: 0` so multi-GB uploads are not cut off.

Apply the Gateway API CRDs **first**. The bundle version must be the one the installed Traefik
documents (v1.6.1 for Traefik 3.7): with an older bundle Traefik logs `Failed to watch
*v1.TLSRoute` forever and never reconciles a `Gateway`. Re-apply on Traefik upgrades.

    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
    helm repo add traefik https://traefik.github.io/charts
    helm upgrade --install traefik traefik/traefik -n traefik --create-namespace -f traefik.values.yml
    kubectl apply -f traefik-middlewares.yaml

Do not apply a `GatewayClass` yourself: with `providers.kubernetesGateway.enabled`, the chart
creates and Helm-owns `traefik`, and a pre-existing one of that name makes the install fail with
"invalid ownership metadata".

`traefik-middlewares.yaml` holds the shared Middlewares in `default`: `https-redirect`,
`www-redirect` and `body-<size>` caps. Ingresses attach them with
`traefik.ingress.kubernetes.io/router.middlewares: default-<name>@kubernetescrd` (comma-separated
for several). An `HTTPRoute` can only reference Middlewares in its own namespace, so Gateway API
apps carry their own copy. Rules worth remembering:

* Redirect HTTP to HTTPS per Ingress with the Middleware, never at the entrypoint: an
  entrypoint-level redirect also catches cert-manager's plain-HTTP solver Ingress and breaks
  issuance.
* Traefik has no default body-size cap (nginx had 1m); attach one only where wanted.
* A hostname that is only a TLS SAN with no route gets a 404, not a redirect. `www.` aliases need
  their own rule plus the `www-redirect` Middleware. This was a brief production bug for konsti.
* New apps should use Gateway API: one `Gateway` per app namespace, since each app has its own
  certificate, with cert-manager issuing to the listener.
* Traefik never retries a failed backend connection on its own, unlike nginx's default
  `proxy_next_upstream`. A pod that is terminating stays in Traefik's backend list for the
  2 s `providersThrottleDuration` plus API propagation, so an app that stops accepting
  connections on SIGTERM (gunicorn, uvicorn) returns 502s on every rollout. Fix it in the app:
  a `preStop` sleep of about 10 s, `maxUnavailable: 0`, and optionally a `retry` Middleware
  (network errors only, no POST) as in kompassi's `kubernetes/manifest.mts`.

### cert-manager

    helm repo add jetstack https://charts.jetstack.io
    helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace -f cert-manager.values.yml
    kubectl apply -f letsencrypt-prod.clusterissuer.yaml

`letsencrypt-prod` has one HTTP-01 solver targeting `ingressClassName: traefik`. A `Certificate`
without an `ownerReference` to its Ingress silently ignores new hosts on that Ingress; check for
that when a cert stops covering a hostname.

Gateway API support is on (`config.gatewayAPI.enabled`), so a `Gateway` annotated with
`cert-manager.io/cluster-issuer` gets a `Certificate` for every HTTPS listener with a hostname
and a `certificateRefs` Secret, no explicit `Certificate` needed. The solver Ingress it creates
still routes through Traefik's Ingress provider next to the app's Gateway; the solver's longer
path rule wins for `/.well-known/acme-challenge/`. garage predates this and keeps its explicit
`Certificate`.

### local-path-provisioner (`local-path-big`)

k3s ships the default `local-path` class on the SSD. A second copy of rancher's
local-path-provisioner chart, in namespace `local-path-provisioner-big`, adds `local-path-big` at
`/mnt/big/localpath` on every node with `local-path-provisioner.values.yaml`. Check the release
name and chart source with `helm list -n local-path-provisioner-big` before upgrading; they are not
recorded here.

Volumes of either class are pinned to the node that first scheduled the pod. A pod using one cannot
move; its workload has to be replicated at the application level (Garage RF3, CloudNativePG
streaming replication), and recovering from a lost node means deleting the PVC and letting the
application re-clone. The `local-path-big` helper pod is a single fixed pod and races when several
PVCs are created at once; one Garage data directory came out `0755` root-owned that way.

### PostgreSQL

Operator, plugin, cluster and the per-app onboarding scripts are all under [`postgres/`](postgres/README.md).
Namespaces: `cnpg-system` for the operator and Barman Cloud plugin (the plugin must share the
operator's namespace), `postgres` for the shared `Cluster`.

### Garage and its off-site mirror

[`garage/README.md`](garage/README.md): installed from a git clone of the Garage repository at a
pinned tag, not from a Helm repo; `meta` on `local-path`, `data` on `local-path-big`; TLS via a
Gateway at garage.con2.fi. [`garage/backup.README.md`](garage/backup.README.md): rclone CronJobs
in namespace `garage-backup` copying the media originals to piilo-s3 with 90 days of version
history.

### redis-ha

    helm repo add dandydev https://dandydeveloper.github.io/charts
    helm upgrade --install redis-ha dandydev/redis-ha --version 4.39.0 -n redis-ha --create-namespace -f redis-ha.values.yml

Apps reach it at `redis-ha-haproxy.redis-ha.svc.cluster.local`.

### GitHub Actions runners

Two Helm releases from the [ARC quickstart](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/quickstart):
the controller in `arc-systems` (`actions-runner-controller.yml`, chart defaults) and the scale set
in `arc-runners` (`actions-runner-scaleset.values.yml`, plus the `qb-arc-runners` ServiceAccount
and RBAC in `actions-runner-scaleset.serviceaccount.yml`). The scale set is idle at zero pods
between jobs. Its ClusterRole needs a rule for every CRD the runners deploy (Traefik Middlewares,
Gateway API kinds, cert-manager Certificates).

## Namespaces and image pull secrets

Application images come from ghcr.io. `create-namespace.sh <ns>` creates a namespace and copies the
`con2-ghcr` (and the legacy `con2-harbor`) pull secrets from `default` into it, binding them to the
namespace's `default` ServiceAccount; `update-imagepullsecret.sh` re-copies them into every
namespace after a token rotation. Namespaces that only run public images (the backup CronJobs,
`postgres`) are created with plain `kubectl create namespace`.
