#!/usr/bin/env bash
set -euo pipefail

# Coordinator-generated: tear down podman compose deployment on ironhide.local

SSH_HOST="ironhide.local"
REMOTE_WORKDIR="/tmp/hypothetest/evaluations"
COMPOSE_DIR="generated/compose"

echo "[teardown] engine=podman host=${SSH_HOST}"

if [[ "${HYPOTHETEST_DRY_RUN:-false}" == "true" ]]; then
  exit 0
fi

ssh "${SSH_HOST}" "cd ${REMOTE_WORKDIR} && podman-compose -f ${COMPOSE_DIR}/compose.yml down -v"

echo "[teardown] complete=true"
