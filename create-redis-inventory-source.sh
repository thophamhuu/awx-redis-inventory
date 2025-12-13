#!/bin/bash

# Script để tạo Redis inventory source qua AWX API
# Vì AWX CLI không hỗ trợ --source-script, nên dùng API trực tiếp

set -e

echo "=== Tạo Redis Inventory Source qua AWX API ==="

# Cấu hình
AWX_URL="http://awx.172.17.196.124.nip.io"
AWX_USER="admin"
AWX_PASSWORD="VMware123!"
INVENTORY_NAME="Redis-Dynamic"
SOURCE_NAME="redis-inline"

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

# Lấy Inventory ID
echo ""
echo "Bước 2: Lấy ID của inventory '$INVENTORY_NAME'..."
INVENTORY_ID=$(awx --conf.host "$AWX_URL" --conf.token "$TOKEN" -k inventory list -f json 2>/dev/null | jq -r ".results[] | select(.name == \"$INVENTORY_NAME\") | .id")

if [ -z "$INVENTORY_ID" ] || [ "$INVENTORY_ID" = "null" ]; then
    echo "Lỗi: Không tìm thấy inventory '$INVENTORY_NAME'"
    exit 1
fi
echo "✓ Inventory ID: $INVENTORY_ID"

# Kiểm tra xem source đã tồn tại chưa
echo ""
echo "Bước 3: Kiểm tra inventory source '$SOURCE_NAME'..."
EXISTING_SOURCE=$(awx --conf.host "$AWX_URL" --conf.token "$TOKEN" -k inventory_source list -f json 2>/dev/null | jq -r ".results[] | select(.name == \"$SOURCE_NAME\" and .inventory == $INVENTORY_ID) | .id")

if [ -n "$EXISTING_SOURCE" ] && [ "$EXISTING_SOURCE" != "null" ]; then
    echo "⚠ Inventory source đã tồn tại (ID: $EXISTING_SOURCE)"
    echo "Để cập nhật, vui lòng xóa và tạo lại hoặc cập nhật qua Web Interface"
    exit 0
fi

# Tạo script content
SCRIPT_CONTENT='#!/usr/bin/env python3
import json, redis, os
r = redis.Redis(host='\''172.17.196.126'\'', port=6379, db=1, decode_responses=True)
hosts = r.smembers('\''ansible:hosts'\'') or []
inv = {'\''_meta'\'': {'\''hostvars'\'': {}}, '\''all'\'': {'\''hosts'\'': list(hosts)}}
for h in hosts: inv['\''_meta'\'']['\''hostvars'\''][h] = r.hgetall(f'\''ansible:facts:{h}'\'') or {}
print(json.dumps(inv))'

# Tạo inventory source qua API
echo ""
echo "Bước 4: Tạo inventory source qua API..."
SCRIPT_JSON=$(echo "$SCRIPT_CONTENT" | jq -Rs .)

RESPONSE=$(curl -s -k -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"$SOURCE_NAME\",
        \"inventory\": $INVENTORY_ID,
        \"source\": \"constructed\",
        \"script\": $SCRIPT_JSON,
        \"update_on_launch\": true
    }" \
    "$AWX_URL/api/v2/inventory_sources/")

# Kiểm tra kết quả
if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
    SOURCE_ID=$(echo "$RESPONSE" | jq -r '.id')
    echo "✓ Inventory source đã được tạo thành công (ID: $SOURCE_ID)"
    echo ""
    echo "Để sync inventory source, chạy:"
    echo "  awx --conf.host \"$AWX_URL\" --conf.token \"\$TOKEN\" -k inventory_source update $SOURCE_ID"
elif echo "$RESPONSE" | jq -e '.script' > /dev/null 2>&1; then
    echo "⚠ Lỗi: API không hỗ trợ tạo custom script trực tiếp"
    echo "Response: $RESPONSE" | jq '.'
    echo ""
    echo "Vui lòng tạo qua Web Interface:"
    echo "1. Truy cập: $AWX_URL"
    echo "2. Inventories > $INVENTORY_NAME > Sources > Add"
    echo "3. Name: $SOURCE_NAME"
    echo "4. Source: Custom Script"
    echo "5. Script: (paste script từ file /tmp/redis_inventory_script.py)"
    echo "6. Update on Launch: ✓"
else
    echo "✗ Lỗi khi tạo inventory source:"
    echo "$RESPONSE" | jq '.' 2>/dev/null || echo "$RESPONSE"
    echo ""
    echo "AWX API không hỗ trợ tạo custom script inventory source trực tiếp."
    echo "Vui lòng tạo qua Web Interface (xem hướng dẫn trên)."
fi

