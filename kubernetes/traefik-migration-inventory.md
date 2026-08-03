# ingress-nginx → Traefik migration inventory

Tracks every live `Ingress` resource in the cluster and its migration status. Update this table as apps move over — see "ingress-nginx to Traefik migration" in `README.md` for the overall approach and the annotation-translation table.

**Approach note (2026-08-03):** the coexistence phase (dual nginx/Traefik annotations per app, gated behind a boolean flag) is being skipped going forward — repos are moved straight to Traefik-only, with nginx-specific annotations/logic removed entirely. `kompassi` and `kompassi-v2-frontend` (which initially went through the coexistence pattern for their staging environments) have been cleaned up to match. Actual deploy timing per app is coordinated manually against the node-level rollout (qb2/qb3 still run only ingress-nginx and carry most production traffic — see `README.md`), so a repo being committed/mergeable here doesn't mean it's safe to deploy immediately.

Last synced against the live cluster: 2026-08-03 (re-verified directly against `kubectl get ingress -A` — several deploys had landed without an explicit report-back, so status below reflects actual cluster state, not just what was reported).

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
| kompassi-production | kompassi | kompassi.eu, conit.fi | **qb2 (.82) + qb3 (.83) — split across one Ingress** | kompassi | 🔧 Pushed — traefik-only, deploy pending manual GitHub environment approval (held until **both** qb2 and qb3 migrate) |
| kompassi-production | kompassi-backup | vara.kompassi.eu | external (185.159.236.140, not in this cluster) | kompassi | 🔧 Pushed — traefik-only, deploy pending manual GitHub environment approval (node-flip-independent; served off-cluster) |
| kompassi2-staging | kompassi2 | v2.dev.kompassi.eu | qb1 (.81) | kompassi-v2-frontend | ✅ Migrated |
| kompassi2-production | kompassi2 | v2.kompassi.eu | qb2 (.82) | kompassi-v2-frontend | 🔧 Pushed — traefik-only, deploy pending manual GitHub environment approval (held until qb2 migrates) |
| ~~larpit-staging~~ | ~~larpit~~ | ~~dev.larpit.fi~~ | — | larpit-fi | ✅ Deleted — environment was stale/not actively deployed; namespace removed 2026-08-03 (DB, which lives outside this namespace, untouched). No cluster-scoped orphans found |
| larpit-production | larpit | larpit.fi | qb2 (.82) | larpit-fi | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`body-1m` middlewares confirmed live. Held until qb2 migrates |
| conikuvat-production | edegal | conikuvat.fi | qb2 (.82) | edegal | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`body-100m` middlewares confirmed live. Held until qb2 migrates |
| conikuvat-staging | edegal | dev.conikuvat.fi | qb2 (.82) | edegal | ✅ Deployed & verified — confirmed `ingressClassName: traefik`; currently dark (nginx dropped the route, qb2 has no Traefik yet) — expected, not a bug. Held until qb2 migrates |
| larppikuvat | edegal | larppikuvat.fi | qb2 (.82) | edegal | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`body-100m` middlewares confirmed live. Held until qb2 migrates |
| ~~empresenten-staging~~ | ~~empresenten~~ | ~~dev.infotv.tracon.fi~~ | — | — | ✅ Deleted — namespace removed 2026-08-03, confirmed no leftover cluster-scoped resources (PVs, ClusterRoles/Bindings, ClusterIssuers, etc.) |
| freescout-tracon | freescout | freescout.tracon.fi | qb2 (.82) | — | 👤 External — own admin |
| infokala | infokala | infokala.tracon.fi | qb2 (.82) | infokala-tracon | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. Held until qb2 migrates |
| infotv | infotv | infotv.tracon.fi | qb2 (.82) | infotv-tracon | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. Held until qb2 migrates |
| ~~infotv~~ | ~~infotv-insecure~~ | ~~infotv-insecure.tracon.fi~~ | external (91.105.252.70, not in this cluster) | infotv-tracon | ⚠️ **Needs manual cleanup** — repo change deployed, but the classless `infotv-insecure` Ingress is still live in-cluster (skaffold doesn't prune removed manifests); needs `kubectl delete ingress -n infotv infotv-insecure` by hand. Note: `infotv-insecure.tracon.fi` still listed in `production.vars.yaml`'s Django `ALLOWED_HOSTS` — harmless, left as-is, optional follow-up cleanup |
| kirppu | kirppu | kirppu.tracon.fi | qb2 (.82) | kirppu | 🤝 2nd party — still `ingressClassName: nginx` live in cluster; PR **not yet merged/deployed**. Held until qb2 migrates |
| kirppu | kirppu-backup | vara.kirppu.tracon.fi | external (185.159.236.140, not in this cluster) | kirppu | 🤝 2nd party — still `nginx` live; PR **not yet merged/deployed**. Node-flip-independent (served off-cluster) |
| kirppu-staging | kirppu | kirppudev.tracon.fi | qb2 (.82) | kirppu | 🤝 2nd party — still `nginx` live; PR **not yet merged/deployed**. Held until qb2 migrates |
| konsti-production | konsti | ropekonsti.fi | qb3 (.83) | konsti | 🤝 2nd party — still `ingressClassName: nginx` live in cluster; **staging already deployed but prod not yet**. Held until qb3 migrates |
| konsti-staging | konsti | dev.ropekonsti.fi | qb2 (.82) | konsti | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`www-redirect` middlewares confirmed live (2nd party merged/deployed this without an explicit heads-up — caught via direct cluster check). Held until qb2 migrates |
| minio | minio | minio.con2.fi | qb3 (.83) | infrastructure (`kubernetes/minio.ingress.yaml`, standalone, not via Helm) | ✅ Applied 2026-08-03 — `ingressClassName: traefik` confirmed live in cluster. Held until qb3 migrates. Legacy install, slated for GarageFS replacement (priority raised) |
| outline | outline | outline.con2.fi | qb3 (.83) | outline (our own fork, `con2` branch) | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. Held until qb3 migrates |
| outline-kotae | outline | wiki.kotae.fi | qb2 (.82) | outline | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. Held until qb2 migrates |
| outline-kuplii | outline | wiki.tamperekuplii.fi | qb2 (.82) | outline | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. Held until qb2 migrates |
| outline-ropecon | outline | wiki.ropecon.fi | qb2 (.82) | outline | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. Held until qb2 migrates |
| outline-tracon | outline | wiki.tracon.fi | qb2 (.82) | outline | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live. Held until qb2 migrates |
| rallly | rallly | rallly.con2.fi | qb3 (.83) | rallly-con2 | ⛔ On hold — replicas: 0, pending other fixes |
| redirects | redirects | tracon.fi, www.tracon.fi, hitpoint.tracon.fi, +40 more | **qb2 (.82) + qb3 (.83) — split across one Ingress** (qb3 hosts: con2.fi, www.con2.fi, doodle.con2.fi, rally.con2.fi, rallly.con2.fi, www.conit.fi; rest qb2) | redirects | ✅ Deployed & verified — `ingressClassName: traefik` confirmed live, no middleware annotation (matches prior intentional behavior). Held until **both** qb2 and qb3 migrate |
| redmine | redmine | pora.tracon.fi | qb2 (.82) | — | ⛔ On hold — replicas: 0, pending other fixes |
| static | static | 2005–2015.tracon.fi, media.tracon.fi, 2024.tracon.fi | qb2 (.82) | static | ✅ Live-patched & verified — `ingressClassName: traefik`, `https-redirect` middleware confirmed live (CI build still broken, needs docker; to be fixed separately). Held until qb2 migrates |
| tracontent-con2 | tracontent | con2.fi | qb3 (.83) | tracontent-premium | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`body-100m` middlewares confirmed live (build issue user was addressing appears resolved). Held until qb3 migrates |
| tracontent-tracon | tracontent | 2015–2023.{hitpoint.,}tracon.fi, blog/r/ry.tracon.fi | qb2 (.82) | tracontent-premium | ✅ Deployed & verified — `ingressClassName: traefik`, `https-redirect`+`body-100m` middlewares confirmed live. Held until qb2 migrates |

**30 Ingress resources currently live in the cluster** (`larpit-staging` and `empresenten-staging` tracked above too, struck through, since both were deleted and are no longer part of this count): **21 deployed+verified, 5 still on `nginx` pending 2nd-party merge (kirppu ×3, konsti-production), 2 on hold, 1 needs manual cleanup (`infotv-insecure`), 1 external, 1 minimal-changes-only.**

### Node cutover batches (derived from the Node column above)

- **qb3-only batch**: konsti-production still pending (2nd party); outline main, tracontent-con2, minio all already deployed and just waiting on the qb3 flip.
- **qb2-only batch**: kirppu (production+staging) still pending (2nd party); kompassi2-production still pending (manual GitHub environment approval); everything else in this batch (larpit-production, edegal ×3, infokala, infotv, konsti-staging, outline ×4, static, tracontent-tracon) is already deployed and just waiting on the qb2 flip.
- **Needs both qb2 and qb3 migrated before it can deploy at all**: kompassi-production (still pending manual approval; single Ingress, `kompassi.eu`→qb2 and `conit.fi`→qb3), redirects (already deployed; single Ingress, ~44 hosts→qb2 and 6 `*.con2.fi`/`conit.fi`-variant hosts→qb3).
- **Node-flip-independent** (served off-cluster or already migrated): kompassi-staging/kompassi2-staging (qb1, already migrated), kompassi-backup and kirppu-backup (external IP 185.159.236.140, still pending on the kompassi/kirppu side respectively), infotv-insecure (external IP 91.105.252.70, needs manual deletion regardless of node flips).
- **Not relevant right now**: rallly, redmine (on hold, replicas: 0); freescout (external admin).

### Still outstanding as of this sync — nothing else to report back on except these

1. **kirppu** PR (production, staging, backup) — not yet merged/deployed by the 2nd-party team.
2. **konsti-production** — staging already deployed, but prod PR/deploy not yet done.
3. **kompassi-production + kompassi-backup** — pushed, waiting on manual GitHub environment approval.
4. **kompassi2-production** — pushed, waiting on manual GitHub environment approval.
5. **infotv-insecure** — stale classless Ingress still live in-cluster, needs a manual `kubectl delete` (repo-side removal already deployed, skaffold didn't prune it).
6. **tracontent-premium build** — user was fixing directly; cluster now shows both tracontent Ingresses already on `traefik`, so this appears resolved, worth a quick confirmation.

Everything else in the qb2/qb3-only batches is deployed and verified — ready for the node flips once the above clears.

Node rollout is tracked separately (not per-app): qb1 and qb4 run Traefik; qb2 and qb3 (carrying most production traffic) still run ingress-nginx. See `README.md`.
