#!/usr/bin/env bash
set -euo pipefail

# Coordinator-generated: tear down podman compose deployment on ironhide.local

SSH_HOST="ironhide.local"
REMOTE_WORKDIR="/tmp/hypothetest/evaluations"
COMPOSE_DIR="generated/compose"

echo "[teardown] engine=podman host=${SSH_HOST} status=start"

if [[ "${HYPOTHETEST_DRY_RUN:-false}" == "true" ]]; then
  echo "[teardown] engine=podman host=${SSH_HOST} status=complete dry_run=true"
  exit 0
fi

TEARDOWN_EXIT=0
ssh "${SSH_HOST}" "cd ${REMOTE_WORKDIR} && podman-compose -f ${COMPOSE_DIR}/compose.yml down -v" || TEARDOWN_EXIT=$?

if [[ "${TEARDOWN_EXIT}" -ne 0 ]]; then
  echo "[teardown] engine=podman host=${SSH_HOST} status=failed exit=${TEARDOWN_EXIT}"
  exit "${TEARDOWN_EXIT}"
fi

echo "[teardown] engine=podman host=${SSH_HOST} status=complete"
