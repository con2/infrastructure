# ingress-nginx → Traefik migration inventory

Tracks every live `Ingress` resource in the cluster and its migration status. Update this table as apps move over — see "ingress-nginx to Traefik migration" in `README.md` for the overall approach and the annotation-translation table.

**Approach note (2026-08-03):** the coexistence phase (dual nginx/Traefik annotations per app, gated behind a boolean flag) is being skipped going forward — repos are moved straight to Traefik-only, with nginx-specific annotations/logic removed entirely. `kompassi` and `kompassi-v2-frontend` (which initially went through the coexistence pattern for their staging environments) have been cleaned up to match. Actual deploy timing per app is coordinated manually against the node-level rollout (qb2/qb3 still run only ingress-nginx and carry most production traffic — see `README.md`), so a repo being committed/mergeable here doesn't mean it's safe to deploy immediately.

Last synced against the live cluster: 2026-08-03.

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

| Namespace | Ingress | Host(s) | Repo | Status |
|---|---|---|---|---|
| kompassi-staging | kompassi | dev.kompassi.eu | kompassi | ✅ Migrated |
| kompassi-production | kompassi | kompassi.eu, conit.fi | kompassi | 🔧 Pushed — traefik-only, deploy pending manual GitHub environment approval (held until qb2/qb3 migrate) |
| kompassi-production | kompassi-backup | vara.kompassi.eu | kompassi | 🔧 Pushed — traefik-only, deploy pending manual GitHub environment approval (held until qb2/qb3 migrate) |
| kompassi2-staging | kompassi2 | v2.dev.kompassi.eu | kompassi-v2-frontend | ✅ Migrated |
| kompassi2-production | kompassi2 | v2.kompassi.eu | kompassi-v2-frontend | 🔧 Pushed — traefik-only, deploy pending manual GitHub environment approval (held until qb2/qb3 migrate) |
| larpit-staging | larpit | dev.larpit.fi | larpit-fi | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |
| larpit-production | larpit | larpit.fi | larpit-fi | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |
| conikuvat-production | edegal | conikuvat.fi | edegal | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |
| conikuvat-staging | edegal | dev.conikuvat.fi | edegal | 🔧 Committed locally (not pushed) — was classless, now explicit `ingressClassName: traefik` |
| larppikuvat | edegal | larppikuvat.fi | edegal | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |
| ~~empresenten-staging~~ | ~~empresenten~~ | ~~dev.infotv.tracon.fi~~ | — | ✅ Deleted — namespace removed 2026-08-03, confirmed no leftover cluster-scoped resources (PVs, ClusterRoles/Bindings, ClusterIssuers, etc.) |
| freescout-tracon | freescout | freescout.tracon.fi | — | 👤 External — own admin |
| infokala | infokala | infokala.tracon.fi | infokala-tracon | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |
| infotv | infotv | infotv.tracon.fi | infotv-tracon | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |
| ~~infotv~~ | ~~infotv-insecure~~ | ~~infotv-insecure.tracon.fi~~ | infotv-tracon | 🔧 Manifest removed from repo (`kubernetes/ingress-insecure.yaml`), committed locally not pushed — cluster resource itself still live, will disappear once deployed. Note: `infotv-insecure.tracon.fi` still listed in `production.vars.yaml`'s Django `ALLOWED_HOSTS` — harmless, left as-is, optional follow-up cleanup |
| kirppu | kirppu | kirppu.tracon.fi | kirppu | 🤝 2nd party — committed on `traefik-migration` branch, not pushed; PR to be opened separately |
| kirppu | kirppu-backup | vara.kirppu.tracon.fi | kirppu | 🤝 2nd party — committed on `traefik-migration` branch, not pushed; PR to be opened separately |
| kirppu-staging | kirppu | kirppudev.tracon.fi | kirppu | 🤝 2nd party — committed on `traefik-migration` branch, not pushed; PR to be opened separately |
| konsti-production | konsti | ropekonsti.fi | konsti | 🤝 2nd party — committed on `traefik-migration` branch, not pushed; PR to be opened separately |
| konsti-staging | konsti | dev.ropekonsti.fi | konsti | 🤝 2nd party — committed on `traefik-migration` branch, not pushed; PR to be opened separately |
| minio | minio | minio.con2.fi | infrastructure (Helm values) | 🧊 Minimal changes only — legacy install, slated for GarageFS replacement |
| outline | outline | outline.con2.fi | outline (our own fork, `con2` branch) | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |
| outline-kotae | outline | wiki.kotae.fi | outline | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |
| outline-kuplii | outline | wiki.tamperekuplii.fi | outline | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |
| outline-ropecon | outline | wiki.ropecon.fi | outline | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |
| outline-tracon | outline | wiki.tracon.fi | outline | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |
| rallly | rallly | rallly.con2.fi | rallly-con2 | ⛔ On hold — replicas: 0, pending other fixes |
| redirects | redirects | tracon.fi, www.tracon.fi, hitpoint.tracon.fi, +48 more | redirects | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy (no redirect middleware, matches prior intentional behavior) |
| redmine | redmine | pora.tracon.fi | — | ⛔ On hold — replicas: 0, pending other fixes |
| static | static | 2005–2015.tracon.fi, media.tracon.fi, 2024.tracon.fi | static | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |
| tracontent-con2 | tracontent | con2.fi | tracontent-premium | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |
| tracontent-tracon | tracontent | 2015–2023.{hitpoint.,}tracon.fi, blog/r/ry.tracon.fi | tracontent-premium | 🔧 Committed locally (not pushed) — traefik-only, awaiting deploy |

**31 Ingress resources currently live in the cluster** (`empresenten-staging` is tracked above too, struck through, since it was already deleted and is no longer part of this count): **2 migrated, 19 committed locally awaiting deploy, 5 2nd-party (PR workflow), 2 on hold, 1 pending deletion (`infotv-insecure`), 1 external, 1 minimal-changes-only.**

Node rollout is tracked separately (not per-app): qb1 and qb4 run Traefik; qb2 and qb3 (carrying most production traffic) still run ingress-nginx. See `README.md`.
