# Sourced by update-secret.sh and migrate-database.sh. Reads how an app's Secret stores its
# database settings. Our apps use one of two shapes:
#
#   - Django apps: keys hostname, database, username, password (exactly these, lower case).
#   - Node apps: key DATABASE_URL, optionally DATABASE_URL_REPLICA for the read replicas.
#
# read_secret_shape NAMESPACE SECRET sets $shape to django, node or none, and $keys to the
# key names present. report_unknown_shape prints why a Secret matched neither, pointing out
# near misses such as POSTGRES_PASSWORD or Hostname.

django_keys="hostname database username password"

read_secret_shape() {
  keys="$(kubectl -n "$1" get secret "$2" -o jsonpath='{.data}' \
    | tr -d '{}"' | tr ',' '\n' | cut -d: -f1)"
  django_missing=""
  for k in $django_keys; do
    has_key "$k" || django_missing="$django_missing $k"
  done
  if [ -z "$django_missing" ]; then
    shape=django
  elif has_key DATABASE_URL; then
    shape=node
  else
    shape=none
  fi
}

has_key() { printf '%s\n' "$keys" | grep -qx "$1"; }

# secret_value NAMESPACE SECRET KEY prints the decoded value.
secret_value() {
  kubectl -n "$1" get secret "$2" -o jsonpath="{.data.$3}" | base64 -d
}

report_unknown_shape() {
  echo "$0: $1/$2 matches neither convention, nothing changed." >&2
  echo "  Django needs: $django_keys (missing:$django_missing)" >&2
  echo "  Node needs:   DATABASE_URL" >&2
  echo "  Keys present:" >&2
  for k in $keys; do
    case " $django_keys DATABASE_URL " in
      *" $k "*) echo "    $k" >&2 ;;
      *) echo "    $k   <- not a database key" >&2 ;;
    esac
  done
  for k in $keys; do
    lower="$(printf '%s' "$k" | tr 'A-Z' 'a-z')"
    for want in $django_keys; do
      if [ "$k" != "$want" ] && { [ "$lower" = "$want" ] || [ "$lower" = "postgres_$want" ]; }; then
        echo "  $k looks like it should be '$want'" >&2
      fi
    done
  done
}
