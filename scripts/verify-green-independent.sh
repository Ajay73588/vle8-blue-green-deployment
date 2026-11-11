#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-vle8-app}"
LOCAL_PORT="${LOCAL_PORT:-18082}"

echo "Testing Green deployment independently via kubectl port-forward (no production traffic change)..."
kubectl port-forward -n "${NAMESPACE}" deployment/myapp-green "${LOCAL_PORT}:80" >/tmp/vle8-green-pf.log 2>&1 &
PF_PID=$!
trap 'kill "${PF_PID}" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 15); do
  if curl -fsS --max-time 2 "http://127.0.0.1:${LOCAL_PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

HEALTH_JSON="$(curl -fsS --max-time 5 "http://127.0.0.1:${LOCAL_PORT}/health")"
HTML_BODY="$(curl -fsS --max-time 5 "http://127.0.0.1:${LOCAL_PORT}/")"
echo "Independent Green /health response: ${HEALTH_JSON}"

echo "${HEALTH_JSON}" | grep -q '"status":"healthy"'
echo "${HEALTH_JSON}" | grep -q '"color":"GREEN"'
echo "${HEALTH_JSON}" | grep -q '"version":"v2"'
echo "${HTML_BODY}" | grep -q 'GREEN'
echo "${HTML_BODY}" | grep -q 'v2'

echo "Independent Green verification PASSED without routing production traffic."
