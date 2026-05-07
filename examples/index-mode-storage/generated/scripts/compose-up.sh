#!/usr/bin/env bash
set -euo pipefail

# Coordinator-generated: start podman compose deployment on ironhide.local
# Remote scope — all compose commands execute via SSH.

SSH_HOST="ironhide.local"
REMOTE_WORKDIR="/tmp/hypothetest/evaluations"
COMPOSE_DIR="generated/compose"
HEALTH_TIMEOUT=120
HEALTH_INTERVAL=5

ES_URL="http://ironhide.local:9200"

echo "[start] engine=podman host=${SSH_HOST} workdir=${REMOTE_WORKDIR}"

if [[ "${HYPOTHETEST_DRY_RUN:-false}" == "true" ]]; then
  echo "[healthy] dry_run=true"
  exit 0
fi

ssh "${SSH_HOST}" mkdir -p "${REMOTE_WORKDIR}/${COMPOSE_DIR}"

scp -q \
  "${COMPOSE_DIR}/compose.yml" \
  "${COMPOSE_DIR}/.env" \
  "${COMPOSE_DIR}/elasticsearch.yml" \
  "${SSH_HOST}:${REMOTE_WORKDIR}/${COMPOSE_DIR}/"

ssh "${SSH_HOST}" "cd ${REMOTE_WORKDIR} && podman-compose -f ${COMPOSE_DIR}/compose.yml up -d"

elapsed=0
while (( elapsed < HEALTH_TIMEOUT )); do
  if curl -sf "${ES_URL}/_cluster/health" | grep -qE '"status":"(green|yellow)"'; then
    echo "[healthy] elapsed=${elapsed}s url=${ES_URL}"
    exit 0
  fi
  sleep "${HEALTH_INTERVAL}"
  elapsed=$(( elapsed + HEALTH_INTERVAL ))
done

echo "[failed] reason=health_timeout elapsed=${elapsed}s"
exit 1
