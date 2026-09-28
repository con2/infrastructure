#!/bin/sh
# Gives one app its own role and database on the shared postgres Cluster, in one go:
#
#     ./create-app-database.sh larpit
#
# Creates the password Secret <app>-db-credentials in namespace postgres (kept as is if it
# already exists, so re-running never rotates a password), then applies a DatabaseRole and a
# Database of the same name. These objects are deliberately not kept in version control; the
# Kubernetes API is the only record of which apps have a database. Hand the credentials to the
# app with update-secret.sh. See README.md.
set -eu

namespace=postgres
cluster=postgres

app="${1:-}"
case "$app" in
  "")
    echo "usage: $0 APP" >&2
    exit 2
    ;;
  *[!a-z0-9_]* | [!a-z]*)
    echo "$0: APP must match [a-z][a-z0-9_]*, got '$app'" >&2
    exit 2
    ;;
esac

secret="$app-db-credentials"
if kubectl -n "$namespace" get secret "$secret" >/dev/null 2>&1; then
  echo "Secret $namespace/$secret already exists, keeping its password"
else
  # Hex only, so the password can be pasted into a URL without escaping.
  kubectl -n "$namespace" create secret generic "$secret" --type=kubernetes.io/basic-auth \
    --from-literal=username="$app" --from-literal=password="$(openssl rand -hex 24)"
fi
# The operator picks up password edits to the Secret only when it carries this label.
kubectl -n "$namespace" label secret "$secret" cnpg.io/reload=true --overwrite >/dev/null

kubectl apply -f - <<YAML
apiVersion: postgresql.cnpg.io/v1
kind: DatabaseRole
metadata:
  name: $app
  namespace: $namespace
spec:
  cluster:
    name: $cluster
  name: $app
  login: true
  passwordSecret:
    name: $secret
  databaseRoleReclaimPolicy: retain
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: $app
  namespace: $namespace
spec:
  cluster:
    name: $cluster
  name: $app
  owner: $app
  # Finnish on ICU, spelled out per database so it holds even if the cluster's template1 is
  # ever changed, and so nobody has to remember it per app as was the case on siilo.
  template: template0
  encoding: UTF8
  localeProvider: icu
  icuLocale: fi-FI
  localeCollate: fi_FI.UTF-8
  localeCType: fi_FI.UTF-8
  databaseReclaimPolicy: retain
YAML

# Database reports readiness as status.applied, not a Ready condition.
for _ in $(seq 1 30); do
  if [ "$(kubectl -n "$namespace" get database "$app" -o jsonpath='{.status.applied}')" = "true" ]; then
    echo "Database $app is ready. Next: ./update-secret.sh $app <namespace> <secret>"
    exit 0
  fi
  sleep 2
done
echo "Database $app not applied after 60s:" >&2
kubectl -n "$namespace" get database "$app" -o jsonpath='{.status.message}{"\n"}' >&2
exit 1
