#!/bin/sh
# Loads a local pg_dump archive into an app's database on the in-cluster postgres Cluster, for
# when migrate-database.sh cannot reach the source directly:
#
#     ./load-dump.sh kompassi ~/kompassi.dump
#     ./load-dump.sh --replace --skip-extension postgres_fdw kompassi ~/kompassi.dump
#
# APP is the role and database created by create-app-database.sh. DUMP is a custom-format
# (pg_dump -Fc) archive. The file is copied to the primary instance and restored there by pg_restore,
# which connects over the local socket as the superuser and restores with SET
# ROLE APP, so the app's role ends up owning every object. The destination must have no tables
# unless --replace is given, which drops and recreates schema public first.
#
# --skip-extension NAME leaves out an extension (and its comment) the dump would create. Needed
# for untrusted extensions such as postgres_fdw, which only a superuser may create; trusted ones
# such as hstore restore fine under the app's role. May be repeated.
set -eu
set -o pipefail

pg_namespace=postgres
cluster=postgres

replace=false
skip_pattern=""
while [ $# -gt 0 ]; do
  case "$1" in
    --replace) replace=true; shift ;;
    --skip-extension) skip_pattern="$skip_pattern|$2"; shift 2 ;;
    --) shift; break ;;
    -*) echo "$0: unknown option $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
if [ $# -ne 2 ]; then
  echo "usage: $0 [--replace] [--skip-extension NAME]... APP DUMP" >&2
  exit 2
fi
app="$1"
dump="$2"

if [ ! -r "$dump" ]; then
  echo "$0: cannot read $dump" >&2
  exit 1
fi
command -v pg_restore >/dev/null || { echo "$0: pg_restore is needed locally to list the archive" >&2; exit 1; }

primary="$(kubectl -n "$pg_namespace" get cluster "$cluster" -o jsonpath='{.status.currentPrimary}')"
if [ -z "$primary" ]; then
  echo "$0: cluster $pg_namespace/$cluster has no current primary" >&2
  exit 1
fi

on_primary() {
  kubectl -n "$pg_namespace" exec -i "$primary" -c postgres -- "$@"
}
sql() {
  on_primary psql -d "$app" -v ON_ERROR_STOP=1 -tA "$@"
}

if [ "$(sql -c "select 1 from pg_roles where rolname = '$app'")" != 1 ]; then
  echo "$0: role $app does not exist; run create-app-database.sh first" >&2
  exit 1
fi

# Dropping only EXTENSION entries keeps a skipped name from also hiding a table that happens to
# contain it.
toc="$(pg_restore -l "$dump" | grep -Ev "^;|^$")"
if [ -n "$skip_pattern" ]; then
  toc="$(printf '%s\n' "$toc" | grep -Ev " EXTENSION (- )?(${skip_pattern#|})( |$)")"
fi

echo "Destination: $primary ($pg_namespace/$cluster) database $app, restoring as role $app"
echo "Archive:     $dump ($(printf '%s\n' "$toc" | wc -l | tr -d ' ') TOC entries)"

tables="$(sql -c "select count(*) from pg_stat_user_tables")"
if [ "$tables" != 0 ]; then
  if [ "$replace" = true ]; then
    echo "Dropping schema public with $tables tables"
    # Same ownership and grants as a fresh PostgreSQL 15+ database, so the app's role may create
    # in it as the database owner.
    sql -c "drop schema public cascade; create schema public authorization pg_database_owner; grant usage on schema public to public;"
  else
    echo "$0: destination already has $tables tables; pass --replace to drop them first" >&2
    exit 1
  fi
fi

echo "== copying archive to $primary"
# The archive and TOC list are copied over first instead of streaming the archive on pg_restore's
# stdin: a long exec with nothing on stdout drops when the API server is reached over a tunnel,
# and copying is quick. The root filesystem is read-only; /tmp may be
# too, in which case the data volume's top level takes the files.
work="$(on_primary sh -c 'mktemp -d 2>/dev/null || mktemp -d -p /var/lib/postgresql/data' </dev/null)"
trap 'on_primary rm -rf "$work" </dev/null' EXIT
printf '%s\n' "$toc" | on_primary sh -c 'cat > "$1/toc.list"' - "$work"
kubectl -n "$pg_namespace" cp -c postgres "$dump" "$primary:$work/archive"

echo "== restoring"
on_primary pg_restore -d "$app" --role="$app" --no-owner --no-acl --exit-on-error --verbose \
  -L "$work/toc.list" "$work/archive" 2>&1 | grep -v '^pg_restore: \(processing\|creating\|connecting\|finished\|launching\|entering\)'

# A bare ANALYZE also tries the shared catalogs and warns about each one it may not touch.
sql -c "select format(\$\$analyze %I.%I;\$\$, schemaname, relname) from pg_stat_user_tables" | on_primary psql -d "$app" -q
echo "== destination row counts"
sql -c "select relname, n_live_tup from pg_stat_user_tables order by 1"

echo "Done. Next: ./update-secret.sh $app <namespace> <secret> if not done yet, then scale the app back up."
