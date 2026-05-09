#!/usr/bin/env bash
set -euo pipefail

# Coordinator-generated: create a k3d cluster for local Kubernetes
# Standalone — can be run independently of eck-up.sh.
# Only runs when kubernetes.provider resolves to k3d.

CLUSTER_NAME="${HYPOTHETEST_K3D_CLUSTER:-hypothetest}"

echo "[start] phase=k3d_install cluster=${CLUSTER_NAME}"

if [[ "${HYPOTHETEST_DRY_RUN:-false}" == "true" ]]; then
  echo "[healthy] phase=k3d_install dry_run=true"
  exit 0
fi

# --- verify Docker is running ---
if ! docker info >/dev/null 2>&1; then
  echo "[failed] phase=k3d_install reason=docker_not_running"
  exit 1
fi

# --- check if cluster already exists ---
if k3d cluster list -o json 2>/dev/null | grep -q "\"name\":\"${CLUSTER_NAME}\""; then
  echo "[ready] phase=k3d_exists cluster=${CLUSTER_NAME}"
  kubectl cluster-info --context "k3d-${CLUSTER_NAME}"
  exit 0
fi

# --- create cluster (single server, no agents, traefik/servicelb disabled) ---
k3d cluster create "${CLUSTER_NAME}" \
  --agents 0 \
  --port "9200:9200@server:0" \
  --k3s-arg "--disable=traefik@server:0" \
  --k3s-arg "--disable=servicelb@server:0" \
  --wait

# --- merge kubeconfig ---
k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-merge-default

# --- wait for node ready ---
TIMEOUT=120
elapsed=0
while (( elapsed < TIMEOUT )); do
  NODE_READY=$(kubectl get nodes --context "k3d-${CLUSTER_NAME}" \
    -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [[ "${NODE_READY}" == "True" ]]; then
    break
  fi
  sleep 5
  elapsed=$(( elapsed + 5 ))
done

if [[ "${NODE_READY}" != "True" ]]; then
  echo "[failed] phase=k3d_install reason=node_not_ready elapsed=${elapsed}s"
  exit 1
fi

echo "[healthy] phase=k3d_install cluster=${CLUSTER_NAME} context=k3d-${CLUSTER_NAME}"
