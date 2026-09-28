#!/bin/sh
# Copies an app's database from wherever its Secret currently points (siilo) into the in-cluster
# postgres Cluster, using a one-off pod running pg_dump | pg_restore:
#
#     ./migrate-database.sh larpit larpit-production larpit
#
# APP is the role and database created by create-app-database.sh. The app's Secret must still
# hold the *old* credentials in one of the shapes described in secret-shape.sh; run this before
# update-secret.sh. Stop the app first so nothing writes during the copy. The destination
# database must be empty; the pod refuses otherwise, so a second run never restores on top of
# data. See README.md.
set -eu
. "$(dirname "$0")/secret-shape.sh"

pg_namespace=postgres
dst_host=postgres-rw.postgres.svc.cluster.local

if [ $# -ne 3 ]; then
  echo "usage: $0 APP APP_NAMESPACE SECRET_NAME" >&2
  exit 2
fi
app="$1"
namespace="$2"
secret="$3"

read_secret_shape "$namespace" "$secret"
case "$shape" in
  django)
    src_host="$(secret_value "$namespace" "$secret" hostname)"
    # siilo only accepts TLS from outside; its certificate is from Let's Encrypt, so the
    # hostname can be verified.
    src_url="postgresql://$(secret_value "$namespace" "$secret" username):$(secret_value "$namespace" "$secret" password)@$src_host:5432/$(secret_value "$namespace" "$secret" database)?sslmode=verify-full"
    ;;
  node)
    src_url="$(secret_value "$namespace" "$secret" DATABASE_URL)"
    src_host="$(printf '%s' "$src_url" | sed -E 's#^[a-z]+://([^@]*@)?([^/:?]+).*#\2#')"
    ;;
  *)
    report_unknown_shape "$namespace" "$secret"
    exit 1
    ;;
esac

case "$src_host" in
  postgres-rw* | postgres-ro* | postgres-r.*)
    echo "$0: $namespace/$secret already points at the in-cluster database ($src_host); nothing to migrate" >&2
    exit 1
    ;;
esac

# libpq verifies certificates against ~/.postgresql/root.crt, which the pod does not have. The
# container's system trust store knows Let's Encrypt, so point libpq at it instead of
# weakening sslmode. An explicit sslrootcert in the app's URL is left alone.
case "$src_url" in
  *sslrootcert=*) ;;
  *\?*) src_url="$src_url&sslrootcert=system" ;;
  *) src_url="$src_url?sslrootcert=system" ;;
esac

dst_password="$(secret_value "$pg_namespace" "$app-db-credentials" password)"
if [ -z "$dst_password" ]; then
  echo "$0: no password in $pg_namespace/$app-db-credentials; run create-app-database.sh first" >&2
  exit 1
fi
dst_url="postgresql://$app:$dst_password@$dst_host:5432/$app?sslmode=disable"

# Same image as the Cluster, so pg_dump is at least as new as either server.
image="$(sed -n 's/^ *imageName: *//p' "$(dirname "$0")/cluster.yaml")"

echo "Source:      $src_host ($shape secret $namespace/$secret)"
echo "Destination: $dst_host database $app"
printf 'Is the app stopped so nothing writes to the source? [y/N] '
read -r answer
case "$answer" in
  y | Y) ;;
  *) echo "aborted"; exit 1 ;;
esac

# Row counts come from pg_stat_user_tables, so the destination is analyzed first to make them
# comparable with the source.
script='
set -eu
tables=$(psql "$DST_URL" -tAc "select count(*) from pg_stat_user_tables")
if [ "$tables" != 0 ]; then
  echo "destination already has $tables tables, refusing to restore on top" >&2
  exit 1
fi
echo "== copying"
pg_dump "$SRC_URL" -Fc --no-owner --no-acl | pg_restore -d "$DST_URL" --no-owner --no-acl --exit-on-error
# A bare ANALYZE also tries the shared catalogs and warns about each one it may not touch.
psql "$DST_URL" -tAc "select format(\$\$analyze %I.%I\$\$, schemaname, relname) from pg_stat_user_tables" | psql "$DST_URL" -q
counts="select relname, n_live_tup from pg_stat_user_tables order by 1"
echo "== source row counts";      psql "$SRC_URL" -tAc "$counts"
echo "== destination row counts"; psql "$DST_URL" -tAc "$counts"
'

# The URLs and the script travel in a short-lived Secret rather than on the pod's command line,
# where anyone who can list pods would see them.
pod="pg-migrate-$app"
trap 'kubectl -n "$pg_namespace" delete secret "$pod" --ignore-not-found >/dev/null' EXIT
kubectl -n "$pg_namespace" create secret generic "$pod" \
  --from-literal=SRC_URL="$src_url" --from-literal=DST_URL="$dst_url" --from-literal=SCRIPT="$script" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl -n "$pg_namespace" run "$pod" --rm -i --restart=Never --image="$image" \
  --overrides="{\"spec\":{\"containers\":[{\"name\":\"$pod\",\"image\":\"$image\",\"command\":[\"sh\",\"-c\",\"eval \\\"\$SCRIPT\\\"\"],\"envFrom\":[{\"secretRef\":{\"name\":\"$pod\"}}]}]}}"

echo "Done. Next: ./update-secret.sh $app $namespace $secret, then restart the app."
