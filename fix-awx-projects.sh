#!/bin/bash

echo "=== Kiểm tra và sửa lỗi AWX Projects ==="

AWX_POD=$(kubectl get pods -n awx -l app.kubernetes.io/name=awx-task --no-headers -o custom-columns=":metadata.name" | head -1)

if [ -z "$AWX_POD" ]; then
    echo "Lỗi: Không tìm thấy AWX task pod"
    exit 1
fi

echo "AWX Pod: $AWX_POD"
echo ""

# Kiểm tra thư mục projects
echo "=== Kiểm tra thư mục /var/lib/awx/projects ==="
kubectl exec -n awx $AWX_POD -- ls -la /var/lib/awx/projects/

echo ""
echo "=== Danh sách thư mục con ==="
kubectl exec -n awx $AWX_POD -- bash -c "cd /var/lib/awx/projects && find . -maxdepth 1 -type d ! -name '.' | sort"

echo ""
echo "=== Kiểm tra file redis_inventory.py trong các thư mục ==="
for dir in redis-inventory redis-inventory-script _redis_inventory; do
    echo "Thư mục: $dir"
    kubectl exec -n awx $AWX_POD -- ls -la /var/lib/awx/projects/$dir/redis_inventory.py 2>/dev/null && echo "  ✓ File tồn tại" || echo "  ✗ File không tồn tại"
done

echo ""
echo "=== Đảm bảo quyền đúng ==="
kubectl exec -n awx $AWX_POD -- bash -c "cd /var/lib/awx/projects && chmod 755 redis-inventory redis-inventory-script _redis_inventory 2>/dev/null; chown -R awx:root redis-inventory redis-inventory-script _redis_inventory 2>/dev/null"

echo ""
echo "=== Thư mục khuyến nghị: redis-inventory ==="
echo "File: /var/lib/awx/projects/redis-inventory/redis_inventory.py"
kubectl exec -n awx $AWX_POD -- cat /var/lib/awx/projects/redis-inventory/redis_inventory.py

echo ""
echo "=== Hướng dẫn ==="
echo "1. Refresh trang web AWX (F5 hoặc Ctrl+R)"
echo "2. Trong dropdown 'Playbook Directory', bạn sẽ thấy các thư mục:"
echo "   - redis-inventory"
echo "   - redis-inventory-script"
echo "   - _redis_inventory"
echo "3. Chọn một trong các thư mục trên"
echo "4. Source Path sẽ là: redis_inventory.py"

