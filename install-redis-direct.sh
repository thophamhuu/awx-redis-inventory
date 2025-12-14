#!/bin/bash

# Script cài đặt trực tiếp redis module vào AWX task pods

set -e

echo "=== Cài đặt redis module trực tiếp vào AWX task pods ==="
echo ""

AWX_NAMESPACE="${AWX_NAMESPACE:-awx}"
CONTAINER="${CONTAINER:-awx-ee}"
REDIS_VERSION="${REDIS_VERSION:-redis>=4.0.0}"

# Tìm tất cả awx-task pods
echo "Bước 1: Tìm AWX task pods..."
TASK_PODS=$(kubectl get pods -n "$AWX_NAMESPACE" -l app.kubernetes.io/name=awx-task -o jsonpath='{.items[*].metadata.name}')

if [ -z "$TASK_PODS" ]; then
    echo "✗ Không tìm thấy task pods"
    exit 1
fi

echo "✓ Tìm thấy các task pods:"
for pod in $TASK_PODS; do
    echo "  - $pod"
done
echo ""

# Cài đặt cho từng pod
SUCCESS_COUNT=0
FAIL_COUNT=0

for pod in $TASK_PODS; do
    echo "Bước 2: Xử lý pod $pod..."
    
    # Kiểm tra xem redis đã được cài đặt chưa
    if kubectl exec -n "$AWX_NAMESPACE" "$pod" -c "$CONTAINER" -- python3 -c "import redis" 2>/dev/null >/dev/null; then
        VERSION=$(kubectl exec -n "$AWX_NAMESPACE" "$pod" -c "$CONTAINER" -- python3 -c "import redis; print(redis.__version__)" 2>/dev/null)
        echo "  ✓ Pod $pod: redis đã được cài đặt (version: $VERSION)"
        ((SUCCESS_COUNT++))
    else
        echo "  ⚠ Pod $pod: redis chưa được cài đặt, đang cài đặt..."
        
        # Cài đặt redis
        if kubectl exec -n "$AWX_NAMESPACE" "$pod" -c "$CONTAINER" -- python3 -m pip install "$REDIS_VERSION" 2>&1; then
            VERSION=$(kubectl exec -n "$AWX_NAMESPACE" "$pod" -c "$CONTAINER" -- python3 -c "import redis; print(redis.__version__)" 2>/dev/null)
            echo "  ✓ Pod $pod: Đã cài đặt thành công redis (version: $VERSION)"
            ((SUCCESS_COUNT++))
        else
            echo "  ✗ Pod $pod: Lỗi khi cài đặt redis"
            ((FAIL_COUNT++))
        fi
    fi
    echo ""
done

echo "=== Kết quả ==="
echo "✓ Thành công: $SUCCESS_COUNT pods"
if [ $FAIL_COUNT -gt 0 ]; then
    echo "✗ Thất bại: $FAIL_COUNT pods"
fi
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
    echo "✓ Module redis đã sẵn sàng trong các task pods!"
    echo ""
    echo "⚠ Lưu ý:"
    echo "  - Cài đặt sẽ mất khi pod restart"
    echo "  - Để cài đặt vĩnh viễn, sử dụng requirements.txt trong AWX Project"
    echo "  - Hoặc tạo custom Execution Environment image"
fi

