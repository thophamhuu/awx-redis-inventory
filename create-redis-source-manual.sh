#!/bin/bash

# Script hướng dẫn tạo Redis inventory source qua Web Interface
# Vì AWX không hỗ trợ custom script qua CLI/API

echo "=== Hướng dẫn tạo Redis Inventory Source ==="
echo ""

# Tạo script file
SCRIPT_FILE="/tmp/redis_inventory_script.py"
cat > "$SCRIPT_FILE" << 'EOF'
#!/usr/bin/env python3
import json, redis, os
r = redis.Redis(host='172.17.196.126', port=6379, db=6, decode_responses=True)
hosts = r.smembers('ansible:hosts') or []
inv = {'_meta': {'hostvars': {}}, 'all': {'hosts': list(hosts)}}
for h in hosts: inv['_meta']['hostvars'][h] = r.hgetall(f'ansible:facts:{h}') or {}
print(json.dumps(inv))
EOF

chmod +x "$SCRIPT_FILE"
echo "✓ Script file đã được tạo: $SCRIPT_FILE"
echo ""

# Hiển thị nội dung script
echo "=== Nội dung script ==="
cat "$SCRIPT_FILE"
echo ""
echo "=== Hướng dẫn tạo qua Web Interface ==="
echo ""
echo "1. Truy cập: http://awx.172.17.196.124.nip.io"
echo "2. Đăng nhập: admin / VMware123!"
echo "3. Vào: Inventories > Redis-Dynamic"
echo "4. Click tab 'Sources'"
echo "5. Click nút 'Add' hoặc '+'"
echo "6. Điền thông tin:"
echo "   - Name: redis-inline"
echo "   - Source: Chọn 'Custom Script' (nếu có) hoặc 'Sourced from a Project'"
echo "   - Script: Copy toàn bộ nội dung từ file $SCRIPT_FILE (hiển thị ở trên)"
echo "   - Update on Launch: ✓ (check box)"
echo "7. Click 'Save'"
echo ""
echo "Sau khi tạo xong, click 'Sync All' để đồng bộ inventory source."
echo ""
echo "=== Kiểm tra sau khi tạo ==="
echo "Chạy lệnh sau để kiểm tra:"
echo "  /home/thoph/check-redis-inventory.sh"

