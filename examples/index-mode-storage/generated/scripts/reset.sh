#!/usr/bin/env bash
set -euo pipefail

# Coordinator-generated: variation reset for index-mode-storage
# Deletes variation index, clears caches, verifies cluster green.

VARIATION="$1"
REPEAT="$2"
ES_URL="${ELASTICSEARCH_URL:-http://ironhide.local:9200}"

variation_index_name() {
    case "$1" in
        standard)                         echo "yelp-reviews-standard" ;;
        logsdb)                           echo "yelp-reviews-logsdb" ;;
        logsdb_synthetic_source)          echo "yelp-reviews-logsdb-synthetic-source" ;;
        standard_best_compression)        echo "yelp-reviews-standard-best-compression" ;;
        standard_best_compression_sorted) echo "yelp-reviews-standard-best-compression-sorted" ;;
        *) echo "benchmark-index" ;;
    esac
}

INDEX_NAME="$(variation_index_name "${VARIATION}")"

echo "[reset] variation=${VARIATION} repeat=${REPEAT}"

if [[ "${HYPOTHETEST_DRY_RUN:-false}" == "true" ]]; then
  exit 0
fi

curl -sf -X DELETE "${ES_URL}/${INDEX_NAME}" -o /dev/null || true
echo "[reset] action=delete_indices index=${INDEX_NAME}"

curl -sf -X POST "${ES_URL}/_cache/clear" -o /dev/null
echo "[reset] action=clear_caches"

health=$(curl -sf "${ES_URL}/_cluster/health?wait_for_status=green&timeout=30s")
status=$(echo "${health}" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

if [[ "${status}" != "green" ]]; then
  echo "[reset] action=verify_cluster_green status=${status} result=failed"
  exit 1
fi

echo "[reset] action=verify_cluster_green status=green"
