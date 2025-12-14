#!/bin/bash

# Script để cài đặt module redis trong AWX runner container

set -e

echo "=== Cài đặt module redis trong AWX runner ==="
echo ""

# Kiểm tra kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Lỗi: kubectl chưa được cài đặt"
    exit 1
fi

# Tìm AWX namespace (mặc định là awx)
AWX_NAMESPACE="${AWX_NAMESPACE:-awx}"

echo "Bước 1: Tìm AWX runner pods..."
RUNNER_PODS=$(kubectl get pods -n "$AWX_NAMESPACE" -l app.kubernetes.io/name=awx,app.kubernetes.io/component=awx-runner -o jsonpath='{.items[*].metadata.name}')

if [ -z "$RUNNER_PODS" ]; then
    echo "⚠ Không tìm thấy AWX runner pods"
    echo "Thử tìm tất cả pods có 'runner' trong tên..."
    RUNNER_PODS=$(kubectl get pods -n "$AWX_NAMESPACE" | grep runner | awk '{print $1}' | head -1)
    
    if [ -z "$RUNNER_PODS" ]; then
        echo "✗ Không tìm thấy runner pod nào"
        echo ""
        echo "Vui lòng chỉ định pod name thủ công:"
        echo "  kubectl get pods -n $AWX_NAMESPACE"
        echo "  export RUNNER_POD=<pod-name>"
        echo "  $0"
        exit 1
    fi
fi

# Lấy pod đầu tiên nếu có nhiều
RUNNER_POD=$(echo $RUNNER_PODS | awk '{print $1}')

echo "✓ Tìm thấy runner pod: $RUNNER_POD"
echo ""

# Kiểm tra xem redis đã được cài đặt chưa
echo "Bước 2: Kiểm tra module redis..."
if kubectl exec -n "$AWX_NAMESPACE" "$RUNNER_POD" -- python3 -c "import redis" 2>/dev/null; then
    echo "✓ Module redis đã được cài đặt"
    REDIS_VERSION=$(kubectl exec -n "$AWX_NAMESPACE" "$RUNNER_POD" -- python3 -c "import redis; print(redis.__version__)" 2>/dev/null)
    echo "  → Version: $REDIS_VERSION"
else
    echo "⚠ Module redis chưa được cài đặt"
    echo ""
    echo "Bước 3: Cài đặt module redis..."
    
    # Thử cài đặt
    if kubectl exec -n "$AWX_NAMESPACE" "$RUNNER_POD" -- pip install redis 2>&1; then
        echo "✓ Module redis đã được cài đặt thành công"
    else
        echo "✗ Lỗi khi cài đặt module redis"
        echo ""
        echo "Thử cài đặt với pip3..."
        if kubectl exec -n "$AWX_NAMESPACE" "$RUNNER_POD" -- pip3 install redis 2>&1; then
            echo "✓ Module redis đã được cài đặt thành công (qua pip3)"
        else
            echo "✗ Vẫn không thể cài đặt"
            echo ""
            echo "Giải pháp thay thế:"
            echo "1. Tạo custom AWX image với redis module"
            echo "2. Sử dụng requirements.txt trong AWX Project"
            exit 1
        fi
    fi
fi

echo ""
echo "=== Hoàn tất! ==="
echo "Module redis đã sẵn sàng trong AWX runner pod: $RUNNER_POD"
echo ""
echo "Lưu ý: Nếu có nhiều runner pods, cần cài đặt cho tất cả:"
for pod in $RUNNER_PODS; do
    echo "  kubectl exec -n $AWX_NAMESPACE $pod -- pip install redis"
done

