# Installing the Qb cluster from scratch

**Qb** is the next-generation hosting platform for Tracon, Conikuvat etc. services. Technology choices include

* [K3s](https://k3s.io) as the Kubernetes distribution
* [Longhorn](https://longhorn.io/) for distributed storage
* [Minio](https://min.io/) for object storage
* [Traefik](https://traefik.io/) (migrating from [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) - see "ingress-nginx to Traefik migration" below)

TODO:

* [ ] Automate Helm chart installations
  * Ansible?
  * Some in-cluster Helm operator/controller?
* [ ] In-cluster PostgreSQL using a PostgreSQL operator:
  * [CrunchyData](https://github.com/CrunchyData/postgres-operator)
  * [Zalando](https://github.com/zalando/postgres-operator)
* [ ] Minio in distributed mode (requires `qb4`)
* [ ] Harbor should probably use external database

## Pre-requisites

* At least 3 VMs
  * Ubuntu 20.04
  * SSH access with sudo
* Ansible, `kubectl`, Helm installed locally
  * For Ansible, using `python3 -m venv` and `pip install ansible` is recommended. Distro package managers may give you a WW2 era version.

## SSH via bastion server

Qb servers only have HTTP/HTTPS open to the world in the network-level firewall. For SSH, `monokkeli` can be used as a bastion server. Add this to your `~/.ssh/config`:

    Host monokkeli
        Hostname monokkeli.tracon.fi

    Host qb1
        Hostname qb1.con2.fi
        ProxyJump monokkeli

    Host qb2
        Hostname qb2.con2.fi
        ProxyJump monokkeli

    Host qb3
        Hostname qb3.con2.fi
        ProxyJump monokkeli

## K3s cluster setup

Setup ssh keys, basic packages, partitions etc:

    ansible-playbook -u root -t k3s-base,k3s-storage qb.yml

Provision initial server (`qb1`):

    ansible-playbook -bKt k3s-initial-server -l qb1 qb.yml

SSH in, find token in `/var/lib/rancher/k3s/server/token`. `ansible-vault edit group_vars/k3s/vault`, put it in `k3s_token`.

Provision other servers:

    ansible-playbook -bKt k3s-server -l qb2,qb3 qb.yml

On each server `qb1` through `qb3` you should be able to use `kubectl` as root.

Note: The `kubectl` binary installed by K3s is hardcoded to use `/etc/rancher/k3s/k3s.yml` as kubeconfig instead of `~/.kube/config`. `KUBECONFIG` env is still respected.

## Accessing the cluster from your workstation

Copy `/etc/rancher/k3s/k3s.yml` over to your workstation. Point `KUBECONFIG` to it. Open an SSH tunnel to one of the servers:

    ssh -fNL 6443:localhost:6443 qb1

Now you should be able to `kubectl` locally for increased happiness and comfort.

## Cluster services

Install the following using Helm:

* [`kubernetes-secret-generator`](https://github.com/mittwald/kubernetes-secret-generator#helm)
* [`traefik`](https://github.com/traefik/traefik-helm-chart) (replacing `ingress-nginx` - see below)
* [`cert-manager`](https://cert-manager.io/docs/installation/kubernetes/#installing-with-helm)
* [`longhorn`](https://longhorn.io/docs/0.8.0/install/install-with-helm/)

In the above the order does not matter, but these must be installed after `longhorn`:

* [`redis-ha`](https://github.com/DandyDeveloper/charts/tree/master/charts/redis-ha)
* [`minio`](https://github.com/minio/charts)
* [`harbor`](https://github.com/goharbor/harbor-helm)

Links above are to Helm installation instructions of each app. If a value file is required, it should be placed in this directory for future reference.

* **Values**: Use values files from this directory.
* **Release name**: The release name should be the same as the application name.
* **Namespace**: Each should go in a namespace of the same name, with the notable exception of `longhorn` that should go in `longhorn-system`.

Using Longhorn as an example:

    helm repo add longhorn https://charts.longhorn.io
    helm install -n longhorn-system -f longhorn.values.yml longhorn longhorn/longhorn

Yes, that's five `longhorn`s in the same command.

## ingress-nginx to Traefik migration

Per-app migration status is tracked in [`traefik-migration-inventory.md`](traefik-migration-inventory.md) - update it as apps move over.

The cluster is migrating its ingress controller from `ingress-nginx` to `traefik`. Both are installed side by side during the migration, using DaemonSets with `hostNetwork: true` and `hostPort` 80/443 (same operational model `ingress-nginx` has always used - not k3s's bundled Traefik, which uses a different ServiceLB/klipper-lb path and was disabled at cluster bootstrap).

Since both controllers bind hostPort 80/443, they can never run on the same node at the same time. Placement is controlled per-node with a label:

    kubectl label node <name> qb.con2.fi/ingress-controller=nginx    # or =traefik

`ingress-nginx.values.yml` and `traefik.values.yml` each carry a matching `nodeSelector`, so relabeling a node is a swap (evicts one controller's pod, schedules the other's), never a steady-state overlap. ingress-nginx's pod has a 5-minute `terminationGracePeriodSeconds` with a connection-draining `preStop` hook, so expect a relabel to take up to ~5 minutes to settle, not instantaneous - the incoming controller's pod will transiently `CrashLoopBackOff` on the hostPort bind until the outgoing one fully exits.

Install Traefik:

    helm repo add traefik https://traefik.github.io/charts
    helm repo update
    helm install traefik traefik/traefik -n traefik --create-namespace -f traefik.values.yml

Also install the Traefik CRDs (Middleware, ServersTransport, IngressRoute, etc. - see the chart's docs for the current recommended install method) and the shared Middlewares:

    kubectl apply -f traefik-middlewares.yaml

Also install the upstream [Gateway API](https://gateway-api.sigs.k8s.io/) CRDs (standard channel) - installed ahead of need so apps can move from `Ingress` to `Gateway`/`HTTPRoute` one at a time later, without a further cluster-level cutover. **Do this before** `helm install traefik` above, not after:

    kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/vX.Y.Z/standard-install.yaml

Don't `kubectl apply` a `GatewayClass` manifest yourself - with `providers.kubernetesGateway.enabled: true` (set in `traefik.values.yml`), the Traefik chart creates and Helm-owns its own `traefik` `GatewayClass`. A separately-applied, non-Helm-owned `GatewayClass` of the same name existing *before* `helm install traefik` runs makes the install fail outright ("cannot be imported into the current release: invalid ownership metadata") - confirmed by reproducing this exact failure in a from-scratch rehearsal (`garagefs-playground`, see its README/PLAN.md). This is why the Gateway API CRDs must still be applied first (the chart's `GatewayClass` template needs the CRD to exist) while the `GatewayClass` object itself is left for the chart to manage.

The `letsencrypt-prod` `ClusterIssuer` carries two HTTP-01 solvers during the migration (see `letsencrypt-prod.clusterissuer.yaml`) - the `nginx` one stays the unconditional default until every node is on Traefik; only then does the `traefik` solver become the default and the `nginx` one gets removed.

### Per-app annotation translation

Every app's `Ingress` stays a plain `networking.k8s.io/v1 Ingress` (no need to convert to Traefik's `IngressRoute` CRD) - just update `ingressClassName` and annotations:

| nginx annotation | Traefik equivalent |
|---|---|
| `cert-manager.io/cluster-issuer` | No change - cert-manager is ingress-controller-agnostic |
| `kubernetes.io/tls-acme: "true"` (legacy) | Replace with `cert-manager.io/cluster-issuer: letsencrypt-prod` |
| `nginx.ingress.kubernetes.io/ssl-redirect` | Attach the shared `https-redirect` Middleware from `traefik-middlewares.yaml` via `traefik.ingress.kubernetes.io/router.middlewares`, only on Ingresses that actually have TLS configured. **Deliberately not** done as a global entrypoint redirect in `traefik.values.yml` - that would also catch cert-manager's plain-HTTP HTTP-01 solver Ingress, which has no annotation-based way to opt out of an entrypoint-level redirect (unlike ingress-nginx, where cert-manager sets `ssl-redirect: false` on the solver Ingress itself), breaking certificate issuance/renewal |
| `nginx.ingress.kubernetes.io/proxy-body-size` / `nginx.org/client-max-body-size` | Attach the matching shared Middleware from `traefik-middlewares.yaml` via `traefik.ingress.kubernetes.io/router.middlewares: default-body-<size>@kubernetescrd` (Traefik has no default cap, unlike nginx's implicit 1m - only attach where a cap is actually wanted) |
| `nginx.ingress.kubernetes.io/proxy-read-timeout` / `proxy-send-timeout` | Try dropping first (Traefik's default forwarding timeouts are effectively unlimited); only add a `ServersTransport` CRD if testing shows a real regression |
| `nginx.ingress.kubernetes.io/enable-access-log: "false"` | Drop; filter at the Loki/Alloy layer instead if log volume becomes an issue |
| `nginx.ingress.kubernetes.io/from-to-www-redirect` | Attach the shared `www-redirect` Middleware from `traefik-middlewares.yaml` |
| `nginx.ingress.kubernetes.io/auth-type` / `auth-secret` / `auth-realm` (basic auth) | A `Middleware` of type `basicAuth`, created per-app as needed (no shared one exists yet) |

Ingresses with no explicit `ingressClassName` should be given one (`traefik`) rather than relying on classless-adoption behaviour, which differs between controllers.

The `router.middlewares` annotation takes a comma-separated list when an app needs more than one (e.g. `default-https-redirect@kubernetescrd,default-body-100m@kubernetescrd`) - see `kompassi/kubernetes/default.vars.yaml` for a worked example that also gates `https-redirect` on whether TLS is actually enabled for that environment.

### Future work: per-app Gateway API migration

Traefik is installed with both the Kubernetes `Ingress` and Gateway API providers enabled from the start, plus the Gateway API CRDs and the chart's own Helm-managed `GatewayClass`, precisely so this can happen later without another shared/cluster-level cutover. Once the ingress-nginx -> Traefik migration is complete and settled, apps can move from `Ingress` to `Gateway`/`HTTPRoute` independently, at their own pace. Recommended pattern: **one `Gateway` per app/namespace** (not one shared cluster-wide `Gateway`), since each app's domain has its own distinct TLS cert - this mirrors today's one-`Ingress`-per-app model and lets cert-manager issue directly to the `Gateway`'s listener via the same `cert-manager.io/cluster-issuer` annotation used today.

## Miscellaneous

### Creating namespaces

If you need a namespace for an application that has images stored in [Con2 Harbor](https://harbor.con2.fi), you need to create an image pull secret in that namespace and bind it to the `default` service account. The `create-namespace.sh` script does just that, using the `con2-harbor` image pull secret in the `default` namespace as reference.

### Longhorn ingress

Longhorn needs ingress only to expose the management UI outside the cluster.

No built-in authentication. Basic authentication in ingress required. See [documentation](https://longhorn.io/docs/0.8.1/deploy/accessing-the-ui/longhorn-ingress/).

It's a good idea to put the unhashed password in a secret, eg. `longhorn-basic-auth-unhashed`, so that your fellow admins can find it and access the UI.