#!/bin/bash
# Supervisor 및 VKS 클러스터에 로그인한 linux 호스트에서 실행합니다.
# IP주소와 token 정보를 가져옵니다.
# 해당 정보를 windows host에서 clusters.txt에 붙여넣기합니다.
# vSphere SSO로 로그인한 token은 제한 시간이 12시간입니다.
# 각 VKS Cluster별로 Service Account를 만들고, 읽기 권한으로 사전에 clusterrole과 clusterrolebinding을 하고서 token에 만료 시간을 길게 부여해서, 모니터링 용도로 사용하는 것도 괜찮습니다.

# --- [1. 환경 설정] ---
OUTPUT_FILE="clusters.txt"
echo "Starting to extract cluster information from kubeconfig..."

# 기존 파일 초기화
> "$OUTPUT_FILE"

# --- [2. 컨텍스트 목록 가져오기] ---
# 각 컨텍스트의 이름, 연결된 클러스터, 연결된 유저 정보를 추출합니다.
CONTEXTS=$(kubectl config view --raw -o jsonpath='{range .contexts[*]}{.name}{" "}{.context.cluster}{" "}{.context.user}{"\n"}{end}')

# --- [3. 데이터 매핑 및 추출] ---
while read -r ctx_name cluster_name user_name; do
    if [ -z "$ctx_name" ]; then continue; fi

    echo " -> Processing Context: $ctx_name"

    # 1. 클러스터 이름을 기준으로 서버 URL 추출
    SERVER_URL=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name==\"$cluster_name\")].cluster.server}")

    # 2. 유저 이름을 기준으로 토큰 추출
    TOKEN=$(kubectl config view --raw -o jsonpath="{.users[?(@.name==\"$user_name\")].user.token}")

    # 3. URL과 토큰이 모두 존재할 경우 파일에 기록
    if [ -n "$SERVER_URL" ] && [ -n "$TOKEN" ]; then
        # 중복 체크 후 기록
        ENTRY="$SERVER_URL, $TOKEN"
        if ! grep -qxF "$ENTRY" "$OUTPUT_FILE"; then
            echo "$ENTRY" >> "$OUTPUT_FILE"
            echo "    [Success] Found URL and Token"
        fi
    else
        echo "    [Skip] Missing URL or Token for this context"
    fi
done <<< "$CONTEXTS"

# --- [4. 결과 확인] ---
if [ -s "$OUTPUT_FILE" ]; then
    echo "--------------------------------------------------"
    echo "[COMPLETE] '$OUTPUT_FILE' has been created."
    echo "Total clusters found: $(wc -l < "$OUTPUT_FILE")"
else
    echo "--------------------------------------------------"
    echo "[Notice] No valid clusters with tokens were found."
    rm "$OUTPUT_FILE"
fi
