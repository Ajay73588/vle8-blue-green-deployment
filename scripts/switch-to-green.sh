#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-vle8-app}"

echo "Verifying GREEN deployment readiness before switching traffic..."
READY_REPLICAS="$(kubectl get deployment myapp-green -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}')"
DESIRED_REPLICAS="$(kubectl get deployment myapp-green -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')"
if [ "${READY_REPLICAS:-0}" -lt "${DESIRED_REPLICAS:-1}" ]; then
  echo "ERROR: myapp-green is not ready (${READY_REPLICAS:-0}/${DESIRED_REPLICAS:-1}). Aborting switch." >&2
  exit 1
fi

echo "Switching myapp-service selector to color=green..."
kubectl patch service myapp-service -n "${NAMESPACE}" \
  -p '{"spec":{"selector":{"app":"myapp","color":"green"}}}'

kubectl get service myapp-service -n "${NAMESPACE}" -o wide
kubectl get endpoints myapp-service -n "${NAMESPACE}"
