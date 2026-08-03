# ingress-nginx → Traefik migration inventory

Tracks every live `Ingress` resource in the cluster and its migration status. Update this table as apps move over — see "ingress-nginx to Traefik migration" in `README.md` for the overall approach and the annotation-translation table.

**Approach note (2026-08-03):** the coexistence phase (dual nginx/Traefik annotations per app, gated behind a boolean flag) is being skipped going forward — repos are moved straight to Traefik-only, with nginx-specific annotations/logic removed entirely. `kompassi` and `kompassi-v2-frontend` (which initially went through the coexistence pattern for their staging environments) have been cleaned up to match.

**Cutover complete (2026-08-03):** all 4 nodes (qb1, qb2, qb3, qb4) are now labeled `qb.con2.fi/ingress-controller=traefik`. The `ingress-nginx` DaemonSet is scaled to 0/0/0 cluster-wide — no ingress-nginx pods remain anywhere. All 27 live Certificates are `Ready=True`. Every deployed app was verified serving correctly via real DNS end-to-end (not `--resolve` overrides) after the flip. Remaining work is Phase 5 (decommission): flip the `letsencrypt-prod` ClusterIssuer's default solver from nginx to traefik, then `helm uninstall ingress-nginx`, then remove the `nginx` IngressClass — see `README.md`.

One pre-existing, unrelated finding surfaced during verification: `dev.conikuvat.fi` (conikuvat-staging) returns 503 because its `edegal`/`celery`/`nginx` deployments are all scaled to 0 replicas — not caused by the migration, same situation as the now-deleted `larpit-staging`. Worth a decision on whether to clean up this namespace too.

Last synced against the live cluster: 2026-08-03 (re-verified directly against `kubectl get ingress -A` after both node flips — several deploys had landed without an explicit report-back, so status below reflects actual cluster state, not just what was reported).

## Status legend

- ✅ **Migrated** — `ingressClassName: traefik`, deployed and DNS-serving live.
- 🔧 **In progress** — repo changes made/being made, not yet deployed to the cluster.
- ⏳ **Not started**
- ⛔ **On hold** — blocked on unrelated fixes, not part of active migration work right now.
- 🗑️ **To be deleted** — being removed rather than migrated.
- 🤝 **2nd party** — owned by a closely-collaborating external dev team; changes go via pull request, not direct commit.
- 🧊 **Minimal changes only** — legacy installation slated for replacement (not a Traefik-migration priority); touch as little as possible.
- 👤 **External** — owned/administered by someone else entirely; coordinate separately, not part of this workstream.

## Inventory

**Node column** is the live DNS target(s) for that Ingress's host(s) — i.e. which node's flip actually affects that app in production. Resolved 2026-08-03 by querying every live Ingress's hosts against public DNS. This determines which apps can be safely batch-deployed+cutover together per node (see `README.md` cutover section) — an app is only safe to deploy its `ingressClassName: traefik` change once **every** node it resolves to is already running Traefik.

| Namespace | Ingress | Host(s) | Node (IP) | Repo | Status |
|---|---|---|---|---|---|
| kompassi-staging | kompassi | dev.kompassi.eu | qb1 (.81) | kompassi | ✅ Migrated |
| kompassi-production | kompassi | kompassi.eu, conit.fi | **qb2 (.82) + qb3 (.83) — split across one Ingress** | kompassi | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`body-100m` middlewares, cert-manager annotation intact. |
| kompassi-production | kompassi-backup | vara.kompassi.eu | external (185.159.236.140, not in this cluster) | kompassi | ✅ Deployed & verified — `ingressClassName: traefik`, same middlewares (no cert-manager annotation, correct — self-signed/manually-managed TLS). Node-flip-independent (served off-cluster) |
| kompassi2-staging | kompassi2 | v2.dev.kompassi.eu | qb1 (.81) | kompassi-v2-frontend | ✅ Migrated |
| kompassi2-production | kompassi2 | v2.kompassi.eu | qb2 (.82) | kompassi-v2-frontend | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`body-100m` middlewares, cert-manager annotation intact. |
| ~~larpit-staging~~ | ~~larpit~~ | ~~dev.larpit.fi~~ | — | larpit-fi | ✅ Deleted — environment was stale/not actively deployed; namespace removed 2026-08-03 (DB, which lives outside this namespace, untouched). No cluster-scoped orphans found |
| larpit-production | larpit | larpit.fi | qb2 (.82) | larpit-fi | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`body-1m` middlewares confirmed live. |
| conikuvat-production | edegal | conikuvat.fi | qb2 (.82) | edegal | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`body-100m` middlewares confirmed live. |
| conikuvat-staging | edegal | dev.conikuvat.fi | qb2 (.82) | edegal | ✅ Deployed & verified — confirmed `ingressClassName: traefik`, routes correctly. Returns 503 as of 2026-08-03, but that's pre-existing and unrelated: `edegal`/`celery`/`nginx` deployments in this namespace are all scaled to 0 replicas (same situation as the now-deleted `larpit-staging`) |
| larppikuvat | edegal | larppikuvat.fi | qb2 (.82) | edegal | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`body-100m` middlewares confirmed live. |
| ~~empresenten-staging~~ | ~~empresenten~~ | ~~dev.infotv.tracon.fi~~ | — | — | ✅ Deleted — namespace removed 2026-08-03, confirmed no leftover cluster-scoped resources (PVs, ClusterRoles/Bindings, ClusterIssuers, etc.) |
| freescout-tracon | freescout | freescout.tracon.fi | qb2 (.82) | — | 👤 External — own admin |
| infokala | infokala | infokala.tracon.fi | qb2 (.82) | infokala-tracon | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. |
| infotv | infotv | infotv.tracon.fi | qb2 (.82) | infotv-tracon | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. |
| ~~infotv~~ | ~~infotv-insecure~~ | ~~infotv-insecure.tracon.fi~~ | external (91.105.252.70, not in this cluster) | infotv-tracon | ✅ Deleted 2026-08-03 — confirmed gone from the cluster. Note: `infotv-insecure.tracon.fi` still listed in `production.vars.yaml`'s Django `ALLOWED_HOSTS` — harmless, left as-is, optional follow-up cleanup |
| kirppu | kirppu | kirppu.tracon.fi | qb2 (.82) | kirppu | 🤝 2nd party — ✅ Deployed & verified, `ingressClassName: traefik`, `https-redirect` middleware confirmed live (merged to `master` and deployed). |
| kirppu | kirppu-backup | vara.kirppu.tracon.fi | external (185.159.236.140, not in this cluster) | kirppu | 🤝 2nd party — ✅ Deployed & verified, `ingressClassName: traefik`, same middleware, no cert-manager annotation (correct, self-signed/manually-managed TLS). Node-flip-independent (served off-cluster) |
| kirppu-staging | kirppu | kirppudev.tracon.fi | qb2 (.82) | kirppu | 🤝 2nd party — ✅ Deployed & verified, `ingressClassName: traefik`, `https-redirect` middleware confirmed live. |
| konsti-production | konsti | ropekonsti.fi | qb3 (.83) | konsti | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`www-redirect` middlewares confirmed live. **Found and fixed a real bug during verification**: `www.ropekonsti.fi` had a TLS cert SAN but no Ingress rule, so Traefik had no route for it at all (404) — nginx's old `from-to-www-redirect` annotation didn't need an explicit rule, Traefik has no equivalent. Mitigated live via `kubectl patch` immediately, then fixed properly in the konsti repo (`main`, commit `f237de36`, not yet PR'd to the team) by adding `www.ropekonsti.fi` to `ingress_public_hostnames`. |
| konsti-staging | konsti | dev.ropekonsti.fi | qb2 (.82) | konsti | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`www-redirect` middlewares confirmed live (2nd party merged/deployed this without an explicit heads-up — caught via direct cluster check). |
| minio | minio | minio.con2.fi | qb3 (.83) | infrastructure (`kubernetes/minio.ingress.yaml`, standalone, not via Helm) | ✅ Applied 2026-08-03 — `ingressClassName: traefik` confirmed live in cluster. Legacy install, slated for GarageFS replacement (priority raised) |
| outline | outline | outline.con2.fi | qb3 (.83) | outline (our own fork, `con2` branch) | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. |
| outline-kotae | outline | wiki.kotae.fi | qb2 (.82) | outline | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. |
| outline-kuplii | outline | wiki.tamperekuplii.fi | qb2 (.82) | outline | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. |
| outline-ropecon | outline | wiki.ropecon.fi | qb2 (.82) | outline | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. |
| outline-tracon | outline | wiki.tracon.fi | qb2 (.82) | outline | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. |
| rallly | rallly | rallly.con2.fi | qb3 (.83) | rallly-con2 | ⛔ On hold — replicas: 0, pending other fixes |
| redirects | redirects | tracon.fi, www.tracon.fi, hitpoint.tracon.fi, +40 more | **qb2 (.82) + qb3 (.83) — split across one Ingress** (qb3 hosts: con2.fi, www.con2.fi, doodle.con2.fi, rally.con2.fi, rallly.con2.fi, www.conit.fi; rest qb2) | redirects | ✅ Deployed & verified — `ingressClassName: traefik` confirmed live, no middleware annotation (matches prior intentional behavior). |
| redmine | redmine | pora.tracon.fi | qb2 (.82) | — | ⛔ On hold — replicas: 0, pending other fixes |
| static | static | 2005–2015.tracon.fi, media.tracon.fi, 2024.tracon.fi | qb2 (.82) | static | ✅ Live-patched & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live (CI build still broken, needs docker; to be fixed separately). |
| tracontent-con2 | tracontent | con2.fi | qb3 (.83) | tracontent-premium | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`body-100m` middlewares confirmed live (build issue user was addressing appears resolved). |
| tracontent-tracon | tracontent | 2015–2023.{hitpoint.,}tracon.fi, blog/r/ry.tracon.fi | qb2 (.82) | tracontent-premium | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`body-100m` middlewares confirmed live. |

**29 Ingress resources currently live in the cluster** (`larpit-staging`, `empresenten-staging`, and `infotv-insecure` tracked above too, struck through, since all three were deleted and are no longer part of this count): **25 deployed+verified, 2 on hold, 1 external, 1 minimal-changes-only.**

### Node cutover: complete (2026-08-03)

Both qb2 and qb3 have been flipped to `traefik`. All 4 nodes now run Traefik; ingress-nginx is fully drained cluster-wide (DaemonSet `0/0/0`, no pods). Every deployed app was re-verified against real DNS after the flip. See the "Cutover complete" note at the top of this file for the full verification summary and the one bug found (konsti's www-redirect) and fixed along the way.

### Still outstanding

1. **conikuvat-staging** (`dev.conikuvat.fi`) — returns 503, but pre-existing/unrelated: its deployments are scaled to 0 replicas. Decide whether to clean up this namespace like `larpit-staging`.
2. **konsti** repo fix (commit `f237de36` on `main`) — not yet PR'd to the konsti team; the live cluster patch is already in place so there's no urgency, just needs the proper fix to land so it survives their next deploy.
3. **Phase 5 (decommission)** — flip `letsencrypt-prod`'s default ACME solver from nginx to traefik (verify with a real renewal), then `helm uninstall ingress-nginx -n ingress-nginx`, then remove the `nginx` IngressClass. Not started yet — recommend a soak period first.

Node rollout: qb1, qb2, qb3, qb4 all run Traefik. See `README.md`.
