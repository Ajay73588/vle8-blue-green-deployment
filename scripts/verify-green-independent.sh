#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-vle8-app}"
LOCAL_PORT="${LOCAL_PORT:-18082}"
PF_LOG="$(mktemp -t vle8-green-pf.XXXXXX.log)"

cleanup() {
  if [ -n "${PF_PID:-}" ]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
  fi
  rm -f "${PF_LOG}"
}
trap cleanup EXIT

echo "Testing Green deployment independently via kubectl port-forward (no production traffic change)..."
kubectl port-forward -n "${NAMESPACE}" deployment/myapp-green "${LOCAL_PORT}:80" >"${PF_LOG}" 2>&1 &
PF_PID=$!

for _ in $(seq 1 15); do
  if curl -fsS --max-time 2 "http://127.0.0.1:${LOCAL_PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS --max-time 5 "http://127.0.0.1:${LOCAL_PORT}/health" >/dev/null 2>&1; then
  echo "ERROR: Port-forward to deployment/myapp-green did not become reachable. Log:" >&2
  cat "${PF_LOG}" >&2 || true
  exit 1
fi

HEALTH_JSON="$(curl -fsS --max-time 5 "http://127.0.0.1:${LOCAL_PORT}/health")"
HTML_BODY="$(curl -fsS --max-time 5 "http://127.0.0.1:${LOCAL_PORT}/")"
echo "Independent Green /health response: ${HEALTH_JSON}"

echo "${HEALTH_JSON}" | grep -q '"status":"healthy"'
echo "${HEALTH_JSON}" | grep -q '"color":"GREEN"'
echo "${HEALTH_JSON}" | grep -q '"version":"v2"'
echo "${HTML_BODY}" | grep -q 'GREEN'
echo "${HTML_BODY}" | grep -q 'v2'

echo "Independent Green verification PASSED without routing production traffic."
