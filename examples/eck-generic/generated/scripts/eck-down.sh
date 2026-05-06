#!/usr/bin/env bash
set -euo pipefail

# Coordinator-generated: tear down ECK-deployed Elasticsearch on Kubernetes
# Generic example — the Coordinator adapts per blueprint.
# Does NOT remove k3s — use k3s-uninstall.sh for that.

NAMESPACE="${HYPOTHETEST_K8S_NAMESPACE:-hypothetest}"
CLUSTER_NAME="hypothetest"
REMOVE_OPERATOR="${HYPOTHETEST_K8S_REMOVE_OPERATOR:-false}"

echo "[teardown] target=kubernetes namespace=${NAMESPACE} status=start"

if [[ "${HYPOTHETEST_DRY_RUN:-false}" == "true" ]]; then
  echo "[teardown] target=kubernetes namespace=${NAMESPACE} status=complete dry_run=true"
  exit 0
fi

# --- kill port-forward by PID file ---
PF_PIDFILE="${HYPOTHETEST_EVALUATION_ROOT:-.}/port-forward.pid"
if [[ -f "${PF_PIDFILE}" ]]; then
  PF_PID=$(cat "${PF_PIDFILE}")
  kill "${PF_PID}" 2>/dev/null || true
  rm -f "${PF_PIDFILE}"
fi

TEARDOWN_EXIT=0

# --- delete Elasticsearch CR ---
if kubectl get elasticsearch "${CLUSTER_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  kubectl delete elasticsearch "${CLUSTER_NAME}" -n "${NAMESPACE}" --timeout=120s || TEARDOWN_EXIT=$?
fi

# --- delete Kibana CR (if present) ---
if kubectl get kibana "${CLUSTER_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  kubectl delete kibana "${CLUSTER_NAME}" -n "${NAMESPACE}" --timeout=60s || TEARDOWN_EXIT=$?
fi

# --- delete namespace ---
if kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  kubectl delete namespace "${NAMESPACE}" --timeout=120s || TEARDOWN_EXIT=$?
fi

# --- optionally remove ECK operator ---
if [[ "${REMOVE_OPERATOR}" == "true" ]]; then
  kubectl delete secret eck-trial-license -n elastic-system 2>/dev/null || true
  if helm list -n elastic-system 2>/dev/null | grep -q elastic-operator; then
    helm uninstall elastic-operator -n elastic-system || TEARDOWN_EXIT=$?
  fi
fi

if [[ "${TEARDOWN_EXIT}" -ne 0 ]]; then
  echo "[teardown] target=kubernetes namespace=${NAMESPACE} status=failed exit=${TEARDOWN_EXIT}"
  exit "${TEARDOWN_EXIT}"
fi

echo "[teardown] target=kubernetes namespace=${NAMESPACE} status=complete"
