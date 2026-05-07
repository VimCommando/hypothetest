#!/usr/bin/env bash
set -euo pipefail

# Coordinator-generated: install k3s for local Kubernetes
# Standalone — can be run independently of eck-up.sh.
# Only runs when kubernetes.provider resolves to k3s.

echo "[start] phase=k3s_install"

if [[ "${HYPOTHETEST_DRY_RUN:-false}" == "true" ]]; then
  echo "[healthy] phase=k3s_install dry_run=true"
  exit 0
fi

# --- check if k3s is already running (assumes systemd — k3s installs as a systemd service) ---
if command -v k3s >/dev/null 2>&1 && systemctl is-active k3s >/dev/null 2>&1; then
  echo "[ready] phase=k3s_exists"
  kubectl cluster-info
  exit 0
fi

# --- install k3s (disable traefik and servicelb to reduce benchmark noise) ---
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -

# --- wait for node ready ---
TIMEOUT=120
elapsed=0
while (( elapsed < TIMEOUT )); do
  NODE_READY=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [[ "${NODE_READY}" == "True" ]]; then
    break
  fi
  sleep 5
  elapsed=$(( elapsed + 5 ))
done

if [[ "${NODE_READY}" != "True" ]]; then
  echo "[failed] phase=k3s_install reason=node_not_ready elapsed=${elapsed}s"
  exit 1
fi

# --- ensure kubectl uses the k3s kubeconfig ---
mkdir -p "${HOME}/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "${HOME}/.kube/k3s-config"
sudo chown "$(id -u):$(id -g)" "${HOME}/.kube/k3s-config"
export KUBECONFIG="${HOME}/.kube/k3s-config"

echo "[healthy] phase=k3s_install node=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
echo ""
echo "Run this in your shell before continuing:"
echo "  export KUBECONFIG=${HOME}/.kube/k3s-config"
