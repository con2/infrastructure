#!/bin/bash
set -xueo pipefail

for SECRETNAME in con2-harbor con2-ghcr; do
  DOCKERCONFIGJSON="$(kubectl get secret -o json $SECRETNAME | jq -r '.data.".dockerconfigjson"')"

  kubectl apply -f - << ENOYAML
apiVersion: v1
kind: Namespace
metadata:
  name: $1
ENOYAML

  kubectl apply -n "$1" -f - << ENOYAML
apiVersion: v1
kind: Secret
type: kubernetes.io/dockerconfigjson
metadata:
  name: $SECRETNAME
data:
  .dockerconfigjson: $DOCKERCONFIGJSON
ENOYAML
done

kubectl patch serviceaccount default -n "$1" -p '{"imagePullSecrets": [{"name": "con2-harbor"}, {"name": "con2-ghcr"}]}'
