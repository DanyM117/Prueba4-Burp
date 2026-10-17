#!/bin/bash
set -e

NAMESPACE="${NAMESPACE:-burp-ns}"
RELEASE_NAME="${RELEASE_NAME:-burp-deployment}"
CHART_DIR="./burp"

echo "=== 1. Configurando repositorio oficial de Helm de PortSwigger ==="
helm repo add bsee https://portswigger.github.io/enterprise-helm-charts/ >/dev/null 2>&1 || true
helm repo update

echo "=== 2. Descargando el chart oficial en '${CHART_DIR}' ==="
rm -rf "${CHART_DIR}" burp-suite-enterprise-edition
helm pull bsee/burp-suite-enterprise-edition --untar
mv burp-suite-enterprise-edition "${CHART_DIR}"

echo "=== 3. Generando values.yml a partir del values.yaml oficial del chart ==="
cp "${CHART_DIR}/values.yaml" values.yml

python3 - << 'PYEOF'
import re

with open("values.yml", "r", encoding="utf-8") as f:
    content = f.read()

replacements = {
    r'(enterpriseServerUsername:\s*)""': r'\g<1>"burp_enterprise"',
    r'(enterpriseServerConnectionUsername:\s*)""': r'\g<1>"burp_enterprise"',
    r'(enterpriseServerPassword:\s*)""': r'\g<1>"ChangeMe123!"',
    r'(scanningResourceUsername:\s*)""': r'\g<1>"burp_agent"',
    r'(scanningResourceConnectionUsername:\s*)""': r'\g<1>"burp_agent"',
    r'(scanningResourcePassword:\s*)""': r'\g<1>"ChangeMe123!"',
}

for pattern, repl in replacements.items():
    content = re.sub(pattern, repl, content)

# Actualizar la línea url: "" dentro del bloque database:
content = re.sub(
    r'(url:\s*)""',
    r'\g<1>"jdbc:postgresql://burp-db:5432/burp_enterprise"',
    content,
    count=1,
)

with open("values.yml", "w", encoding="utf-8") as f:
    f.write(content)

with open("./burp/values.yaml", "w", encoding="utf-8") as f:
    f.write(content)
PYEOF

echo "=== 4. Integrando PVC y Base de Datos dentro de './burp/templates/prereqs.yml' ==="
CHART_PVC=$(grep -E "persistentVolumeClaim|pvcName|claimName" values.yml | head -n 1 | awk -F': ' '{print $2}' | tr -d '"' | tr -d "'" | tr -d ' ' || true)
CHART_PVC="${CHART_PVC:-bsee-pvc}"

cat << EOF > "${CHART_DIR}/templates/prereqs.yml"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${CHART_PVC}
  namespace: {{ .Release.Namespace }}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: burp-db-init
  namespace: {{ .Release.Namespace }}
data:
  init.sql: |
    CREATE USER burp_enterprise WITH PASSWORD 'ChangeMe123!';
    CREATE USER burp_agent WITH PASSWORD 'ChangeMe123!';
    GRANT ALL PRIVILEGES ON DATABASE burp_enterprise TO burp_enterprise;
    GRANT ALL ON SCHEMA public TO burp_enterprise;
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: burp-db
  namespace: {{ .Release.Namespace }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: burp-db
  template:
    metadata:
      labels:
        app: burp-db
    spec:
      containers:
        - name: postgres
          image: postgres:15
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: "burp_enterprise"
            - name: POSTGRES_PASSWORD
              value: "ChangeMe123!"
          volumeMounts:
            - name: init-sql
              mountPath: /docker-entrypoint-initdb.d
      volumes:
        - name: init-sql
          configMap:
            name: burp-db-init
---
apiVersion: v1
kind: Service
metadata:
  name: burp-db
  namespace: {{ .Release.Namespace }}
spec:
  selector:
    app: burp-db
  ports:
    - port: 5432
      targetPort: 5432
EOF

kubectl delete namespace "${NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true

echo "=== 5. Ejecutando comando único de instalación de Helm ==="
helm install -n "${NAMESPACE}" "${RELEASE_NAME}" "${CHART_DIR}" -f values.yml --create-namespace

echo "=== 6. Estado del despliegue en el namespace '${NAMESPACE}' (para captura de evidencia): ==="
helm list -n "${NAMESPACE}"
kubectl get deployments,pods,svc,pvc -n "${NAMESPACE}"