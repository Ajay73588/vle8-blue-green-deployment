#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?Usage: $0 <image:tag>}"

if command -v minikube >/dev/null 2>&1 && minikube status >/dev/null 2>&1; then
  echo "Loading ${IMAGE} into Minikube via minikube image load..."
  minikube image load "${IMAGE}"
elif docker ps --format '{{.Names}}' | grep -qx 'minikube'; then
  loaded=false
  if docker exec minikube pgrep -x dockerd >/dev/null 2>&1; then
    echo "Loading ${IMAGE} into Minikube dockerd..."
    docker save "${IMAGE}" | docker exec -i minikube docker load
    loaded=true
  fi
  if docker exec minikube pgrep -x containerd >/dev/null 2>&1 && docker exec minikube which ctr >/dev/null 2>&1; then
    echo "Importing ${IMAGE} into Minikube containerd (k8s.io)..."
    docker save "${IMAGE}" | docker exec -i minikube ctr -n k8s.io images import -
    loaded=true
  fi
  if [ "${loaded}" = "false" ]; then
    echo "ERROR: Could not detect dockerd or containerd inside minikube container." >&2
    exit 1
  fi
else
  echo "ERROR: Minikube is not running." >&2
  exit 1
fi
