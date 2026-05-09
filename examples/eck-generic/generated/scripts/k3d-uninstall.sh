#!/usr/bin/env bash
set -euo pipefail

# Coordinator-generated: cleanly remove a k3d cluster
# Standalone — can be run independently of eck-down.sh.
# Removes containers, volumes, network, and kubeconfig context.

CLUSTER_NAME="${HYPOTHETEST_K3D_CLUSTER:-hypothetest}"

echo "[teardown] phase=k3d_uninstall status=start cluster=${CLUSTER_NAME}"

if [[ "${HYPOTHETEST_DRY_RUN:-false}" == "true" ]]; then
  echo "[teardown] phase=k3d_uninstall status=complete dry_run=true"
  exit 0
fi

# --- idempotent: if cluster doesn't exist, exit cleanly ---
if ! k3d cluster list -o json 2>/dev/null | grep -q "\"name\":\"${CLUSTER_NAME}\""; then
  echo "[teardown] phase=k3d_uninstall status=complete reason=not_found"
  exit 0
fi

k3d cluster delete "${CLUSTER_NAME}"

echo "[teardown] phase=k3d_uninstall status=complete cluster=${CLUSTER_NAME}"
