#!/bin/bash

echo "=== Kiểm tra Redis Dynamic Inventory trên AWX ==="

# Cấu hình AWX
AWX_URL="http://awx.172.17.196.124.nip.io"
AWX_USER="admin"
AWX_PASSWORD="VMware123!"

# Đảm bảo PATH có ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

# Đăng nhập và lấy token
echo ""
echo "Bước 1: Đăng nhập vào AWX..."
LOGIN_OUTPUT=$(awx login --conf.host "$AWX_URL" --conf.username "$AWX_USER" --conf.password "$AWX_PASSWORD" -f json 2>/dev/null)
TOKEN=$(echo "$LOGIN_OUTPUT" | jq -r '.token' 2>/dev/null)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "Lỗi: Không thể đăng nhập"
    exit 1
fi

echo "✓ Đăng nhập thành công"

# Kiểm tra Inventory
echo ""
echo "Bước 2: Kiểm tra Inventory 'Redis-Dynamic'..."
INVENTORY=$(awx --conf.host "$AWX_URL" --conf.token "$TOKEN" -k inventory list -f json 2>/dev/null | jq -r '.results[] | select(.name == "Redis-Dynamic") | {id, name, url}')

if [ -n "$INVENTORY" ]; then
    echo "✓ Inventory 'Redis-Dynamic' đã tồn tại:"
    echo "$INVENTORY" | jq '.'
    INVENTORY_ID=$(echo "$INVENTORY" | jq -r '.id')
else
    echo "✗ Inventory 'Redis-Dynamic' chưa tồn tại"
    exit 1
fi

# Kiểm tra Inventory Source
echo ""
echo "Bước 3: Kiểm tra Inventory Source 'redis-inline'..."
INVENTORY_SOURCE=$(awx --conf.host "$AWX_URL" --conf.token "$TOKEN" -k inventory_source list -f json 2>/dev/null | jq -r ".results[] | select(.name == \"redis-inline\") | {id, name, source, inventory, status, last_updated}")

if [ -n "$INVENTORY_SOURCE" ]; then
    echo "✓ Inventory Source 'redis-inline' đã tồn tại:"
    echo "$INVENTORY_SOURCE" | jq '.'
    SOURCE_ID=$(echo "$INVENTORY_SOURCE" | jq -r '.id')
    
    # Kiểm tra status
    STATUS=$(echo "$INVENTORY_SOURCE" | jq -r '.status')
    echo ""
    echo "Trạng thái: $STATUS"
    
    # Nếu có ID, thử sync để test
    if [ -n "$SOURCE_ID" ]; then
        echo ""
        echo "Bước 4: Đồng bộ Inventory Source để test..."
        echo "Đang chạy sync (có thể mất vài giây)..."
        SYNC_RESULT=$(awx --conf.host "$AWX_URL" --conf.token "$TOKEN" -k inventory_source update "$SOURCE_ID" 2>&1)
        echo "$SYNC_RESULT"
        
        # Đợi một chút rồi kiểm tra lại status
        sleep 3
        UPDATED_STATUS=$(awx --conf.host "$AWX_URL" --conf.token "$TOKEN" -k inventory_source get "$SOURCE_ID" -f json 2>/dev/null | jq -r '{status, last_job_run, last_update_failed, last_updated}')
        echo ""
        echo "Trạng thái sau sync:"
        echo "$UPDATED_STATUS" | jq '.'
    fi
else
    echo "✗ Inventory Source 'redis-inline' chưa tồn tại"
    exit 1
fi

# Kiểm tra Hosts trong Inventory
echo ""
echo "Bước 5: Kiểm tra Hosts trong Inventory..."
HOSTS=$(awx --conf.host "$AWX_URL" --conf.token "$TOKEN" -k inventory get "$INVENTORY_ID" hosts -f json 2>/dev/null | jq -r '.results[] | {id, name, description}')

if [ -n "$HOSTS" ]; then
    echo "✓ Danh sách hosts:"
    echo "$HOSTS" | jq -s '.'
    HOST_COUNT=$(echo "$HOSTS" | jq -s '. | length')
    echo ""
    echo "Tổng số hosts: $HOST_COUNT"
else
    echo "⚠ Chưa có hosts nào trong inventory (có thể cần sync inventory source)"
fi

echo ""
echo "=== Hoàn tất kiểm tra ==="
echo ""
echo "Để kiểm tra trên Web Interface:"
echo "1. Truy cập: $AWX_URL"
echo "2. Đăng nhập với: $AWX_USER / $AWX_PASSWORD"
echo "3. Vào: Inventories > Redis-Dynamic"
echo "4. Tab 'Sources' > Xem 'redis-inline'"
echo "5. Click 'Sync All' để đồng bộ inventory source"
echo "6. Tab 'Hosts' để xem danh sách hosts từ Redis"

