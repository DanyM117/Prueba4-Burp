#!/bin/bash
set -e

NAMESPACE="${NAMESPACE:-burp-ns}"
RELEASE_NAME="${RELEASE_NAME:-burp-deployment}"

echo "=== 1. Desinstalando release de Helm '${RELEASE_NAME}' en el namespace '${NAMESPACE}' ==="
helm uninstall "${RELEASE_NAME}" -n "${NAMESPACE}" || true

echo "=== 2. Eliminando recursos adicionales y namespace '${NAMESPACE}' ==="
kubectl delete namespace "${NAMESPACE}" --ignore-not-found

echo "=== Desinstalación completada exitosamente ==="