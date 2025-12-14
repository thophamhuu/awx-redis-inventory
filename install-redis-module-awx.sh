#!/bin/bash

# Script để cài đặt module redis trong AWX task container
# Lưu ý: AWX Execution Environment thường là read-only và không có pip
# Giải pháp tốt nhất: Sử dụng requirements.txt trong AWX Project

set -e

echo "=== Cài đặt module redis trong AWX task container ==="
echo ""
echo "⚠ Lưu ý: AWX Execution Environment thường không cho phép cài đặt packages"
echo "   Giải pháp khuyến nghị: Sử dụng requirements.txt trong AWX Project"
echo ""

# Kiểm tra kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Lỗi: kubectl chưa được cài đặt"
    exit 1
fi

# Tìm AWX namespace (mặc định là awx)
AWX_NAMESPACE="${AWX_NAMESPACE:-awx}"

echo "Bước 1: Tìm AWX task pods (chạy jobs/tasks)..."
# AWX Operator sử dụng awx-task pods thay vì awx-runner
TASK_PODS=$(kubectl get pods -n "$AWX_NAMESPACE" -l app.kubernetes.io/name=awx-task -o jsonpath='{.items[*].metadata.name}')

if [ -z "$TASK_PODS" ]; then
    echo "⚠ Không tìm thấy AWX task pods với label selector"
    echo "Thử tìm pods có 'task' trong tên..."
    TASK_PODS=$(kubectl get pods -n "$AWX_NAMESPACE" | grep -E "awx-task|task" | grep Running | awk '{print $1}' | head -1)
    
    if [ -z "$TASK_PODS" ]; then
        echo "✗ Không tìm thấy task pod nào"
        echo ""
        echo "Vui lòng chỉ định pod name thủ công:"
        echo "  kubectl get pods -n $AWX_NAMESPACE"
        echo "  export RUNNER_POD=<pod-name>"
        echo "  $0"
        exit 1
    fi
fi

# Lấy pod đầu tiên nếu có nhiều
RUNNER_POD=$(echo $TASK_PODS | awk '{print $1}')

echo "✓ Tìm thấy task pod: $RUNNER_POD"
echo ""

# Tìm container đúng (thường là 'awx-task' hoặc 'awx-ee' trong AWX Operator)
echo "Bước 1.1: Tìm container chạy Python..."
CONTAINER=""
for container in awx-task awx-ee task awx ansible; do
    if kubectl exec -n "$AWX_NAMESPACE" "$RUNNER_POD" -c "$container" -- python3 --version 2>/dev/null >/dev/null; then
        CONTAINER="$container"
        echo "✓ Tìm thấy container: $container"
        break
    fi
done

if [ -z "$CONTAINER" ]; then
    # Thử không chỉ định container (dùng container mặc định)
    if kubectl exec -n "$AWX_NAMESPACE" "$RUNNER_POD" -- python3 --version 2>/dev/null >/dev/null; then
        CONTAINER=""
        echo "✓ Sử dụng container mặc định"
    else
        echo "⚠ Không tìm thấy container Python"
        echo "Thử với container 'awx-task' (mặc định cho AWX Operator)..."
        CONTAINER="awx-task"
    fi
fi

if [ -n "$CONTAINER" ]; then
    CONTAINER_ARG="-c $CONTAINER"
    echo "  → Sử dụng container: $CONTAINER"
else
    CONTAINER_ARG=""
    echo "  → Sử dụng container mặc định"
fi

echo ""

# Kiểm tra xem redis đã được cài đặt chưa
echo "Bước 2: Kiểm tra module redis..."
if kubectl exec -n "$AWX_NAMESPACE" "$RUNNER_POD" $CONTAINER_ARG -- python3 -c "import redis" 2>/dev/null; then
    echo "✓ Module redis đã được cài đặt"
    REDIS_VERSION=$(kubectl exec -n "$AWX_NAMESPACE" "$RUNNER_POD" $CONTAINER_ARG -- python3 -c "import redis; print(redis.__version__)" 2>/dev/null)
    echo "  → Version: $REDIS_VERSION"
else
    echo "⚠ Module redis chưa được cài đặt"
    echo ""
    echo "Bước 3: Cài đặt module redis..."
    
    # Thử cài đặt với python3 -m pip (thường có sẵn trong container)
    if kubectl exec -n "$AWX_NAMESPACE" "$RUNNER_POD" $CONTAINER_ARG -- python3 -m pip install redis 2>&1; then
        echo "✓ Module redis đã được cài đặt thành công (qua python3 -m pip)"
    else
        echo "✗ Lỗi khi cài đặt với python3 -m pip"
        echo ""
        echo "Thử cài đặt với pip..."
        if kubectl exec -n "$AWX_NAMESPACE" "$RUNNER_POD" $CONTAINER_ARG -- pip install redis 2>&1; then
            echo "✓ Module redis đã được cài đặt thành công (qua pip)"
        else
            echo "✗ Lỗi khi cài đặt với pip"
            echo ""
            echo "Thử cài đặt với pip3..."
            if kubectl exec -n "$AWX_NAMESPACE" "$RUNNER_POD" $CONTAINER_ARG -- pip3 install redis 2>&1; then
                echo "✓ Module redis đã được cài đặt thành công (qua pip3)"
            else
                echo "✗ Vẫn không thể cài đặt"
                echo ""
                echo "⚠ Lưu ý: Container có thể là read-only hoặc không có quyền cài đặt"
                echo ""
                echo "Giải pháp thay thế:"
                echo "1. Sử dụng requirements.txt trong AWX Project (Khuyến nghị)"
                echo "2. Tạo custom AWX Execution Environment (EE) image với redis module"
                echo "3. Cài đặt trong virtual environment của project"
                echo ""
                echo "Xem hướng dẫn chi tiết trong FIX-REDIS-MODULE-ERROR.md"
                exit 1
            fi
        fi
    fi
fi

echo ""
echo "=== Hoàn tất! ==="
if [ -n "$CONTAINER" ]; then
    echo "Module redis đã sẵn sàng trong AWX task pod: $RUNNER_POD (container: $CONTAINER)"
else
    echo "Module redis đã sẵn sàng trong AWX task pod: $RUNNER_POD"
fi
echo ""
echo "Lưu ý:"
echo "  - Nếu có nhiều task pods, cần cài đặt cho tất cả"
echo "  - Cài đặt sẽ mất khi pod restart (trừ khi dùng custom image)"
echo "  - Khuyến nghị: Sử dụng requirements.txt trong AWX Project"
echo ""
if [ -n "$TASK_PODS" ] && [ $(echo $TASK_PODS | wc -w) -gt 1 ]; then
    echo "Các task pods khác cần cài đặt:"
    for pod in $TASK_PODS; do
        if [ "$pod" != "$RUNNER_POD" ]; then
            if [ -n "$CONTAINER" ]; then
                echo "  kubectl exec -n $AWX_NAMESPACE $pod -c $CONTAINER -- pip install redis"
            else
                echo "  kubectl exec -n $AWX_NAMESPACE $pod -- pip install redis"
            fi
        fi
    done
fi

