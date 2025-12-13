# AWX Redis Dynamic Inventory

Scripts và tools để thiết lập Redis Dynamic Inventory cho AWX.

## Files

- `redis_inventory.py` - Script Python để lấy inventory từ Redis
- `setup-redis-inventory.sh` - Script tự động thiết lập inventory và source
- `check-redis-inventory.sh` - Script kiểm tra inventory và source
- `create-redis-inventory-source.sh` - Script tạo inventory source qua API
- `create-redis-source-manual.sh` - Hướng dẫn tạo inventory source thủ công
- `fix-awx-projects.sh` - Script kiểm tra và sửa lỗi AWX projects

## Cấu hình Redis

Script kết nối đến Redis:
- Host: 172.17.196.126
- Port: 6379
- Database: 6

## Cấu trúc dữ liệu Redis

- Set `ansible:hosts` - Danh sách hostnames
- Hash `ansible:facts:{hostname}` - Facts của từng host

## Sử dụng

1. Copy `redis_inventory.py` vào `/var/lib/awx/projects/` trong AWX pod
2. Tạo Project trong AWX với Source Control Type = Manual
3. Tạo Inventory Source với Source = "Sourced from a Project"
4. Sync inventory source để lấy hosts từ Redis

Xem chi tiết trong các script và file hướng dẫn.
