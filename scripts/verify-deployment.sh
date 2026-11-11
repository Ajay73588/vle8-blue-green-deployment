#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-vle8-app}"
TARGET_URL="${1:-http://127.0.0.1}"
EXPECTED_COLOR="${2:-}"
EXPECTED_VERSION="${3:-}"

echo "=== Kubernetes Cluster & Workload Status ==="
kubectl get nodes
kubectl get deployments -n "${NAMESPACE}"
kubectl get pods -n "${NAMESPACE}" -o wide
kubectl get services -n "${NAMESPACE}"
kubectl get endpoints -n "${NAMESPACE}"

echo "=== Service Selector ==="
kubectl get service myapp-service -n "${NAMESPACE}" -o jsonpath='{.spec.selector}'; echo

echo "=== Live HTTP Health & Info (${TARGET_URL}) ==="
HEALTH_JSON="$(curl -fsS --max-time 10 "${TARGET_URL}/health")"
INFO_JSON="$(curl -fsS --max-time 10 "${TARGET_URL}/api/info")"
echo "Health: ${HEALTH_JSON}"
echo "Info:   ${INFO_JSON}"

if [ -n "${EXPECTED_COLOR}" ]; then
  echo "${HEALTH_JSON}" | grep -q "\"color\":\"${EXPECTED_COLOR}\"" || {
    echo "ERROR: Expected color ${EXPECTED_COLOR}, got: ${HEALTH_JSON}" >&2
    exit 1
  }
fi

if [ -n "${EXPECTED_VERSION}" ]; then
  echo "${HEALTH_JSON}" | grep -q "\"version\":\"${EXPECTED_VERSION}\"" || {
    echo "ERROR: Expected version ${EXPECTED_VERSION}, got: ${HEALTH_JSON}" >&2
    exit 1
  }
fi

echo "Verification PASSED."
