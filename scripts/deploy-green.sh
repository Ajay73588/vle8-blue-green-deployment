#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-vle8-app}"
IMAGE_TAG="${1:-myapp:v2}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl apply -f "${ROOT_DIR}/kubernetes/namespace.yaml"
kubectl apply -f "${ROOT_DIR}/kubernetes/deployment-green.yaml"
if [ "${IMAGE_TAG}" != "myapp:v2" ]; then
  kubectl set image -n "${NAMESPACE}" deployment/myapp-green myapp="${IMAGE_TAG}"
fi
kubectl rollout status -n "${NAMESPACE}" deployment/myapp-green --timeout=180s
kubectl get deployments,pods -n "${NAMESPACE}" -l app=myapp,color=green -o wide
