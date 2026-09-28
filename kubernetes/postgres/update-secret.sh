#!/bin/sh
# Writes an app's in-cluster database credentials into the Secret the app reads:
#
#     ./update-secret.sh larpit larpit-production larpit
#
# APP is the role and database name created by create-app-database.sh. The target Secret must
# already exist and use one of the two shapes described in secret-shape.sh. Only the database
# keys are touched; anything else in the Secret stays. A Secret matching neither shape is left
# alone and the mismatch is reported. Restart the app afterwards. See README.md.
set -eu
. "$(dirname "$0")/secret-shape.sh"

source_namespace=postgres
host=postgres-rw.postgres.svc.cluster.local
# Streaming replicas only; apps that read DATABASE_URL_REPLICA send public reads here.
ro_host=postgres-ro.postgres.svc.cluster.local
port=5432

if [ $# -ne 3 ]; then
  echo "usage: $0 APP TARGET_NAMESPACE SECRET_NAME" >&2
  exit 2
fi
app="$1"
namespace="$2"
secret="$3"

password="$(secret_value "$source_namespace" "$app-db-credentials" password)"
if [ -z "$password" ]; then
  echo "$0: no password in $source_namespace/$app-db-credentials; run create-app-database.sh first" >&2
  exit 1
fi

read_secret_shape "$namespace" "$secret"
case "$shape" in
  django)
    kubectl -n "$namespace" patch secret "$secret" --type=merge -p "{\"stringData\":{
      \"hostname\":\"$host\",\"database\":\"$app\",\"username\":\"$app\",\"password\":\"$password\"}}"
    echo "Updated $namespace/$secret keys: $django_keys (Django convention)"
    echo "sslmode=require (set elsewhere, e.g. POSTGRES_SSLMODE) works; verify-ca/verify-full would not."
    ;;
  node)
    url="postgresql://$app:$password@$host:$port/$app?sslmode=disable"
    replica_url="postgresql://$app:$password@$ro_host:$port/$app?sslmode=disable"
    kubectl -n "$namespace" patch secret "$secret" --type=merge -p "{\"stringData\":{
      \"DATABASE_URL\":\"$url\",\"DATABASE_URL_REPLICA\":\"$replica_url\"}}"
    echo "Updated $namespace/$secret keys: DATABASE_URL, DATABASE_URL_REPLICA (Node convention)"
    ;;
  *)
    report_unknown_shape "$namespace" "$secret"
    exit 1
    ;;
esac
