#!/bin/bash

# --- [설정 변수] ---
SA_NAME="reader"
NAMESPACE="default"  # ServiceAccount가 생성될 네임스페이스
CLUSTER_ROLE_NAME="cluster-read-only"

echo "=================================================="
echo " Starting Kubernetes User Creation Process"
echo " ServiceAccount: $SA_NAME"
echo " ClusterRole:    $CLUSTER_ROLE_NAME"
echo "=================================================="

# 1. ClusterRole 생성 (모든 리소스에 대한 get, list, watch 권한)
echo -e "\n[1] Creating ClusterRole..."
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $CLUSTER_ROLE_NAME
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- nonResourceURLs: ["*"]
  verbs: ["get"]
EOF

# 2. ServiceAccount 생성
echo -e "\n[2] Creating ServiceAccount..."
if ! kubectl get sa "$SA_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl create sa "$SA_NAME" -n "$NAMESPACE"
    echo " -> ServiceAccount '$SA_NAME' created."
else
    echo " -> ServiceAccount '$SA_NAME' already exists."
fi

# 3. ClusterRoleBinding 생성
echo -e "\n[3] Creating ClusterRoleBinding..."
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${SA_NAME}-binding
subjects:
- kind: ServiceAccount
  name: $SA_NAME
  namespace: $NAMESPACE
roleRef:
  kind: ClusterRole
  name: $CLUSTER_ROLE_NAME
  apiGroup: rbac.authorization.k8s.io
EOF

# 4. Long-lived Token 생성 (K8s 1.24+ 대응)
echo -e "\n[4] Creating Token Secret for ServiceAccount..."
SECRET_NAME="${SA_NAME}-token"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $SECRET_NAME
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/service-account.name: $SA_NAME
type: kubernetes.io/service-account-token
EOF

# 5. 토큰 추출 및 출력
echo -e "\n[5] Extracting Token..."
# 토큰이 생성될 때까지 잠시 대기
sleep 2

TOKEN=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.token}' | base64 --decode)

echo "--------------------------------------------------"
echo " User Creation Complete!"
echo "--------------------------------------------------"
echo "Server URL: $(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
echo "Token:"
echo "$TOKEN"
echo "--------------------------------------------------"

# clusters.txt 형식으로 저장 (선택 사항)
# echo "$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'), $TOKEN" > k8s_reader_token.txt
# echo " -> Saved to k8s_reader_token.txt"