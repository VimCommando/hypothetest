#!/usr/bin/env bash
set -euo pipefail

# Coordinator-generated: cleanly remove k3s
# Standalone — can be run independently of eck-down.sh.
# Removes the k3s binary, systemd service, all containers, all data,
# and the kubeconfig. Returns the machine to pre-install state.

echo "[teardown] phase=k3s_uninstall status=start"

if [[ "${HYPOTHETEST_DRY_RUN:-false}" == "true" ]]; then
  echo "[teardown] phase=k3s_uninstall status=complete dry_run=true"
  exit 0
fi

if [[ ! -f /usr/local/bin/k3s-uninstall.sh ]]; then
  echo "[teardown] phase=k3s_uninstall status=complete reason=not_installed"
  exit 0
fi

/usr/local/bin/k3s-uninstall.sh

rm -f "${HOME}/.kube/k3s-config"

echo "[teardown] phase=k3s_uninstall status=complete"
