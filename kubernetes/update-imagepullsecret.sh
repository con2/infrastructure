#!/bin/bash
set -ueo pipefail

DOCKERCONFIGJSON="$(kubectl get secret -o json con2-harbor | jq -r '.data.".dockerconfigjson"')"
NAMESPACES="$(kubectl get ns -o json | jq -r '.items[].metadata.name')"

for ns in $NAMESPACES; do
    kubectl patch secret con2-harbor -n "$ns" -p "{\"data\": {\".dockerconfigjson\": \"$DOCKERCONFIGJSON\"}}" || true
done