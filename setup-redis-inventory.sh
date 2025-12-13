#!/bin/bash

set -e

echo "=== Thiết lập Redis Dynamic Inventory cho AWX ==="

# Kiểm tra và cài đặt pip nếu chưa có
echo ""
echo "Bước 0.1: Kiểm tra pip..."
if ! command -v pip3 &> /dev/null && ! python3 -m pip --version &> /dev/null; then
    echo "pip3 chưa được cài đặt, đang cài đặt..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y python3-pip
    elif command -v yum &> /dev/null; then
        sudo yum install -y python3-pip
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y python3-pip
    else
        echo "Lỗi: Không tìm thấy package manager để cài đặt pip"
        exit 1
    fi
    echo "✓ pip3 đã được cài đặt"
else
    echo "✓ pip3 đã có sẵn"
fi

# Kiểm tra và cài đặt AWX CLI nếu chưa có
echo ""
echo "Bước 0.2: Kiểm tra AWX CLI..."
if ! command -v awx &> /dev/null; then
    echo "AWX CLI chưa được cài đặt, đang cài đặt..."
    
    # Thử cài đặt qua pipx (cách tốt nhất cho CLI tools)
    if command -v pipx &> /dev/null; then
        echo "Đang cài đặt AWX CLI qua pipx..."
        pipx install ansible-awx 2>/dev/null || pipx install awxkit 2>/dev/null
        export PATH="$HOME/.local/bin:$PATH"
    # Nếu không có pipx, thử cài pipx trước
    elif command -v apt-get &> /dev/null; then
        echo "Đang cài đặt pipx..."
        sudo apt-get install -y pipx
        pipx ensurepath
        export PATH="$HOME/.local/bin:$PATH"
        pipx install ansible-awx 2>/dev/null || pipx install awxkit 2>/dev/null
    # Fallback: sử dụng --break-system-packages
    else
        echo "Đang cài đặt AWX CLI với --break-system-packages..."
        python3 -m pip install --break-system-packages --user ansible-awx 2>/dev/null || \
        python3 -m pip install --break-system-packages --user awxkit 2>/dev/null || {
            echo "Lỗi: Không thể cài đặt AWX CLI. Vui lòng cài đặt thủ công:"
            echo "  sudo apt-get install -y pipx && pipx install ansible-awx"
            exit 1
        }
        export PATH="$HOME/.local/bin:$PATH"
    fi
    
    # Kiểm tra lại xem awx đã được cài đặt chưa
    if ! command -v awx &> /dev/null; then
        echo "Lỗi: AWX CLI vẫn chưa có sẵn sau khi cài đặt. Vui lòng kiểm tra lại."
        exit 1
    fi
    echo "✓ AWX CLI đã được cài đặt"
else
    echo "✓ AWX CLI đã có sẵn"
fi

# Cấu hình AWX
AWX_URL="http://awx.172.17.196.124.nip.io"
AWX_USER="admin"
AWX_PASSWORD="VMware123!"

# Đảm bảo PATH có ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

# Đăng nhập vào AWX và lấy token
echo ""
echo "Bước 1: Đăng nhập vào AWX..."
LOGIN_OUTPUT=$(awx login --conf.host "$AWX_URL" --conf.username "$AWX_USER" --conf.password "$AWX_PASSWORD" -f json 2>/dev/null)

if [ -z "$LOGIN_OUTPUT" ]; then
    echo "Lỗi: Không thể đăng nhập vào AWX (không có output)"
    exit 1
fi

# Extract token bằng jq hoặc python
if command -v jq &> /dev/null; then
    TOKEN=$(echo "$LOGIN_OUTPUT" | jq -r '.token' 2>/dev/null)
elif command -v python3 &> /dev/null; then
    TOKEN=$(echo "$LOGIN_OUTPUT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('token', ''))" 2>/dev/null)
else
    TOKEN=$(echo "$LOGIN_OUTPUT" | grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
fi

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "Lỗi: Không thể lấy token từ phản hồi đăng nhập"
    echo "Output: $LOGIN_OUTPUT"
    exit 1
fi

echo "✓ Đăng nhập thành công"

# 1. Kiểm tra và tạo inventory, lấy ID
echo ""
echo "Bước 2: Kiểm tra/Tạo inventory 'Redis-Dynamic'..."

# Kiểm tra xem inventory đã tồn tại chưa
INVENTORY_ID=$(awx --conf.host "$AWX_URL" --conf.token "$TOKEN" -k inventory list -f json 2>/dev/null | jq -r '.results[] | select(.name == "Redis-Dynamic") | .id')

if [ -n "$INVENTORY_ID" ] && [ "$INVENTORY_ID" != "null" ]; then
    echo "✓ Inventory đã tồn tại (ID: $INVENTORY_ID)"
else
    # Tạo inventory mới
    echo "Đang tạo inventory mới..."
    INVENTORY_OUTPUT=$(awx --conf.host "$AWX_URL" --conf.token "$TOKEN" -k inventory create --name "Redis-Dynamic" --organization Default -f json 2>/dev/null)
    
    if echo "$INVENTORY_OUTPUT" | jq -e '.id' > /dev/null 2>&1; then
        INVENTORY_ID=$(echo "$INVENTORY_OUTPUT" | jq -r '.id')
        echo "✓ Inventory đã được tạo (ID: $INVENTORY_ID)"
    else
        echo "Lỗi: Không thể tạo inventory"
        echo "Output: $INVENTORY_OUTPUT"
        exit 1
    fi
fi

# 2. Tạo script file và kiểm tra inventory source
echo ""
echo "Bước 3: Tạo script file cho inventory source..."

# Tạo script file
SCRIPT_FILE="/tmp/redis_inventory_script.py"
cat > "$SCRIPT_FILE" << 'SCRIPT_EOF'
#!/usr/bin/env python3
import json, redis, os
r = redis.Redis(host='172.17.196.126', port=6379, db=6, decode_responses=True)
hosts = r.smembers('ansible:hosts') or []
inv = {'_meta': {'hostvars': {}}, 'all': {'hosts': list(hosts)}}
for h in hosts: inv['_meta']['hostvars'][h] = r.hgetall(f'ansible:facts:{h}') or {}
print(json.dumps(inv))
SCRIPT_EOF

chmod +x "$SCRIPT_FILE"
echo "✓ Script file đã được tạo: $SCRIPT_FILE"

# Kiểm tra xem inventory source đã tồn tại chưa
echo ""
echo "Bước 4: Kiểm tra inventory source 'redis-inline'..."
EXISTING_SOURCE=$(awx --conf.host "$AWX_URL" --conf.token "$TOKEN" -k inventory_source list -f json 2>/dev/null | jq -r ".results[] | select(.name == \"redis-inline\" and .inventory == $INVENTORY_ID) | .id")

if [ -n "$EXISTING_SOURCE" ] && [ "$EXISTING_SOURCE" != "null" ]; then
    echo "✓ Inventory source đã tồn tại (ID: $EXISTING_SOURCE)"
    echo ""
    echo "Để cập nhật script, vui lòng:"
    echo "1. Vào: $AWX_URL"
    echo "2. Inventories > Redis-Dynamic > Sources > redis-inline"
    echo "3. Tab 'Details' > Paste script từ file: $SCRIPT_FILE"
else
    echo "⚠ Inventory source chưa tồn tại"
    echo ""
    echo "AWX API không hỗ trợ tạo custom script inventory source trực tiếp."
    echo "Vui lòng tạo qua Web Interface:"
    echo ""
    echo "1. Truy cập: $AWX_URL"
    echo "2. Đăng nhập: $AWX_USER / $AWX_PASSWORD"
    echo "3. Vào: Inventories > Redis-Dynamic > Tab 'Sources' > Click 'Add'"
    echo "4. Điền thông tin:"
    echo "   - Name: redis-inline"
    echo "   - Source: Chọn 'Custom Script' (hoặc 'Sourced from a Project' nếu có)"
    echo "   - Script: Copy nội dung từ file $SCRIPT_FILE"
    echo "   - Update on Launch: ✓ (check)"
    echo "5. Click 'Save'"
    echo ""
    echo "Nội dung script:"
    echo "---"
    cat "$SCRIPT_FILE"
    echo "---"
fi

echo ""
echo "=== Hoàn tất! ==="
echo "✓ Inventory 'Redis-Dynamic' đã được kiểm tra/tạo (ID: $INVENTORY_ID)"
echo "✓ Script file đã được tạo: $SCRIPT_FILE"
if [ -n "$EXISTING_SOURCE" ] && [ "$EXISTING_SOURCE" != "null" ]; then
    echo "✓ Inventory source 'redis-inline' đã tồn tại (ID: $EXISTING_SOURCE)"
else
    echo "⚠ Inventory source 'redis-inline' cần được tạo qua Web Interface (xem hướng dẫn trên)"
fi

