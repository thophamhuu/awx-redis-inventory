#!/bin/bash

# Script cài đặt redis vào /tmp/redis-packages trong AWX task pods
# Đây là giải pháp khi không có quyền cài vào system packages

set -e

echo "=== Cài đặt redis vào /tmp/redis-packages trong AWX task pods ==="
echo ""

AWX_NAMESPACE="${AWX_NAMESPACE:-awx}"
CONTAINER="${CONTAINER:-awx-task}"
REDIS_VERSION="${REDIS_VERSION:-redis>=4.0.0}"
INSTALL_DIR="/tmp/redis-packages"

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
    
    # Tìm Python version
    PYTHON_CMD=""
    for py in python3.11 python3 python3.9; do
        if kubectl exec -n "$AWX_NAMESPACE" "$pod" -c "$CONTAINER" -- $py --version 2>/dev/null >/dev/null; then
            PYTHON_CMD=$py
            break
        fi
    done
    
    if [ -z "$PYTHON_CMD" ]; then
        echo "  ✗ Không tìm thấy Python trong container $CONTAINER"
        ((FAIL_COUNT++))
        continue
    fi
    
    echo "  → Python: $PYTHON_CMD"
    
    # Kiểm tra xem redis đã được cài đặt chưa (với PYTHONPATH)
    if kubectl exec -n "$AWX_NAMESPACE" "$pod" -c "$CONTAINER" -- bash -c "export PYTHONPATH=$INSTALL_DIR:\$PYTHONPATH && $PYTHON_CMD -c 'import redis'" 2>/dev/null >/dev/null; then
        VERSION=$(kubectl exec -n "$AWX_NAMESPACE" "$pod" -c "$CONTAINER" -- bash -c "export PYTHONPATH=$INSTALL_DIR:\$PYTHONPATH && $PYTHON_CMD -c 'import redis; print(redis.__version__)'" 2>/dev/null)
        echo "  ✓ redis đã được cài đặt (version: $VERSION)"
        ((SUCCESS_COUNT++))
    else
        echo "  ⚠ redis chưa được cài đặt, đang cài đặt vào $INSTALL_DIR..."
        
        # Cài đặt redis vào /tmp
        if kubectl exec -n "$AWX_NAMESPACE" "$pod" -c "$CONTAINER" -- $PYTHON_CMD -m pip install --target "$INSTALL_DIR" "$REDIS_VERSION" 2>&1 | grep -v "WARNING\|notice" | tail -3; then
            VERSION=$(kubectl exec -n "$AWX_NAMESPACE" "$pod" -c "$CONTAINER" -- bash -c "export PYTHONPATH=$INSTALL_DIR:\$PYTHONPATH && $PYTHON_CMD -c 'import redis; print(redis.__version__)'" 2>/dev/null)
            if [ -n "$VERSION" ]; then
                echo "  ✓ Đã cài đặt thành công redis (version: $VERSION)"
                echo "  → Đã cài vào: $INSTALL_DIR"
                echo "  → Script redis_inventory.py sẽ tự động sử dụng thư mục này"
                ((SUCCESS_COUNT++))
            else
                echo "  ⚠ Đã cài đặt nhưng không thể import"
                ((FAIL_COUNT++))
            fi
        else
            echo "  ✗ Lỗi khi cài đặt redis"
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
    echo "✓ Module redis đã sẵn sàng trong /tmp/redis-packages!"
    echo ""
    echo "⚠ Lưu ý:"
    echo "  - Cài đặt sẽ mất khi pod restart"
    echo "  - Script redis_inventory.py đã được cập nhật để tự động sử dụng /tmp/redis-packages"
    echo "  - Để cài đặt vĩnh viễn, sử dụng requirements.txt trong AWX Project"
fi

