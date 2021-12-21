#!/bin/bash
set -ueo pipefail

for SECRETNAME in con2-harbor con2-ghcr; do
    DOCKERCONFIGJSON="$(kubectl get secret -o json $SECRETNAME | jq -r '.data.".dockerconfigjson"')"
    NAMESPACES="$(kubectl get ns -o json | jq -r '.items[].metadata.name')"

    for ns in $NAMESPACES; do
        kubectl apply -n "$ns" -f - << ENOYAML
apiVersion: v1
kind: Secret
type: kubernetes.io/dockerconfigjson
metadata:
  name: $SECRETNAME
data:
  .dockerconfigjson: $DOCKERCONFIGJSON
ENOYAML

        kubectl patch serviceaccount default -n "$ns" -p '{"imagePullSecrets": [{"name": "con2-harbor"}, {"name": "con2-ghcr"}]}'
    done
done
