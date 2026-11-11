#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-vle8-app}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl apply -f "${ROOT_DIR}/kubernetes/namespace.yaml"
kubectl apply -f "${ROOT_DIR}/kubernetes/deployment-blue.yaml"
kubectl apply -f "${ROOT_DIR}/kubernetes/service.yaml"
kubectl rollout status -n "${NAMESPACE}" deployment/myapp-blue --timeout=180s
kubectl get deployments,pods,svc,endpoints -n "${NAMESPACE}" -o wide
