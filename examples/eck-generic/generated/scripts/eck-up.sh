#!/usr/bin/env bash
set -euo pipefail

# Coordinator-generated: deploy Elasticsearch via ECK operator on Kubernetes
# Generic example — the Coordinator adapts per blueprint.

NAMESPACE="${HYPOTHETEST_K8S_NAMESPACE:-hypothetest}"
ECK_DIR="generated/eck"
HEALTH_TIMEOUT=300
HEALTH_INTERVAL=10
INSTALL_OPERATOR="${HYPOTHETEST_K8S_INSTALL_OPERATOR:-true}"
ECK_OPERATOR_VERSION="${HYPOTHETEST_K8S_OPERATOR_VERSION:-3.3.2}"
CLUSTER_NAME="hypothetest"
SECURITY_ENABLED="${HYPOTHETEST_K8S_SECURITY:-false}"

echo "[start] target=kubernetes namespace=${NAMESPACE} operator_version=${ECK_OPERATOR_VERSION}"

if [[ "${HYPOTHETEST_DRY_RUN:-false}" == "true" ]]; then
  echo "[healthy] dry_run=true"
  exit 0
fi

# --- ECK operator ---
if [[ "${INSTALL_OPERATOR}" == "true" ]]; then
  if ! kubectl get statefulset elastic-operator -n elastic-system >/dev/null 2>&1; then
    echo "[start] phase=operator_install"
    helm repo add elastic https://helm.elastic.co 2>/dev/null || true
    helm repo update elastic
    helm install elastic-operator elastic/eck-operator \
      --namespace elastic-system \
      --create-namespace \
      --version "${ECK_OPERATOR_VERSION}"
    kubectl rollout status statefulset/elastic-operator -n elastic-system --timeout=120s
    echo "[ready] phase=operator_install"
  else
    echo "[ready] phase=operator_exists"
  fi
else
  if ! kubectl get statefulset elastic-operator -n elastic-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q '[1-9]'; then
    echo "[failed] reason=operator_not_running"
    exit 1
  fi
  echo "[ready] phase=operator_verified"
fi

# --- trial license (default true: plan declares enterprise_trial with accept_eula) ---
if [ "${HYPOTHETEST_APPLY_TRIAL_LICENSE:-true}" = "true" ]; then
  echo "[start] phase=trial_license"
  kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: eck-trial-license
  namespace: elastic-system
  labels:
    license.k8s.elastic.co/type: enterprise_trial
  annotations:
    elastic.co/eula: accepted
EOF
  echo "[complete] phase=trial_license"
else
  echo "[skip] phase=trial_license reason=not_requested"
  echo "Set HYPOTHETEST_APPLY_TRIAL_LICENSE=true to apply an enterprise trial license"
fi

# --- namespace + CRDs (kustomize base/overlay) ---
VARIATION="${HYPOTHETEST_VARIATION:-default-heap}"
echo "[start] phase=apply_variation variation=${VARIATION}"
kubectl apply -k "${ECK_DIR}/overlays/${VARIATION}"

if [[ -f "${ECK_DIR}/base/kibana.yaml" ]]; then
  kubectl apply -f "${ECK_DIR}/base/kibana.yaml"
fi

# --- wait for Elasticsearch health ---
echo "[start] phase=waiting_for_health timeout=${HEALTH_TIMEOUT}s"
elapsed=0
while (( elapsed < HEALTH_TIMEOUT )); do
  PHASE=$(kubectl get elasticsearch "${CLUSTER_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  HEALTH=$(kubectl get elasticsearch "${CLUSTER_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.health}' 2>/dev/null || echo "")

  if [[ "${PHASE}" == "Ready" && "${HEALTH}" == "green" ]]; then
    break
  fi

  sleep "${HEALTH_INTERVAL}"
  elapsed=$(( elapsed + HEALTH_INTERVAL ))
done

if [[ "${PHASE}" != "Ready" || "${HEALTH}" != "green" ]]; then
  echo "[failed] reason=health_timeout elapsed=${elapsed}s phase=${PHASE} health=${HEALTH}"
  exit 1
fi

# --- resolve ELASTICSEARCH_URL ---
if [[ "${SECURITY_ENABLED}" == "true" ]]; then
  ES_PASSWORD=$(kubectl get secret "${CLUSTER_NAME}-es-elastic-user" -n "${NAMESPACE}" \
    -o go-template='{{.data.elastic | base64decode}}')
  ES_SCHEME="https"
else
  ES_SCHEME="http"
fi

# --- port-forward for local access ---
PF_PIDFILE="${HYPOTHETEST_EVALUATION_ROOT:-.}/port-forward.pid"
cleanup_pf() { kill "${PF_PID}" 2>/dev/null || true; rm -f "${PF_PIDFILE}"; }
trap cleanup_pf INT TERM

kubectl port-forward -n "${NAMESPACE}" "service/${CLUSTER_NAME}-es-http" 9200:9200 &
PF_PID=$!
echo "${PF_PID}" > "${PF_PIDFILE}"

sleep 2
if ! kill -0 "${PF_PID}" 2>/dev/null; then
  rm -f "${PF_PIDFILE}"
  echo "[failed] reason=port_forward_failed"
  exit 1
fi

ES_URL="${ES_SCHEME}://localhost:9200"

# --- verify cluster responds ---
CURL_ARGS=("-sf")
if [[ "${SECURITY_ENABLED}" == "true" ]]; then
  CURL_ARGS+=("-k" "-u" "elastic:${ES_PASSWORD}")
fi

if curl "${CURL_ARGS[@]}" "${ES_URL}/_cluster/health" | grep -qE '"status":"(green|yellow)"'; then
  trap - INT TERM
  echo "[healthy] elapsed=${elapsed}s url=${ES_URL} port_forward_pid=${PF_PID}"
  exit 0
fi

echo "[failed] reason=cluster_unreachable elapsed=${elapsed}s"
kill "${PF_PID}" 2>/dev/null || true
rm -f "${PF_PIDFILE}"
exit 1
