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

### Cách 1: Sử dụng AWX Project (Khuyến nghị)

1. Tạo Project trong AWX:
   - Name: `redis-inventory` (hoặc tên khác)
   - Source Control Type: `Manual`
   - Copy file `redis_inventory.py` vào project qua Web Interface

2. Cài đặt dependencies:
   - Trong Project settings, thêm `requirements.txt` với nội dung: `redis>=4.0.0`
   - Hoặc cài đặt thủ công trong AWX runner:
     ```bash
     kubectl exec -n awx <awx-runner-pod> -- pip install redis
     ```

3. Tạo Inventory Source:
   - Vào Inventory > Sources > Add
   - Source: `Sourced from a Project`
   - Project: Chọn project `redis-inventory`
   - Source Path: `redis_inventory.py`
   - Update on Launch: ✓ (check)

4. Sync inventory source để lấy hosts từ Redis

### Cách 2: Custom Script Inventory Source

1. Tạo Inventory Source với Source = `Custom Script`
2. Copy nội dung từ `redis_inventory.py` vào script field
3. **Quan trọng**: Đảm bảo module `redis` đã được cài đặt trong AWX runner container

### Cài đặt module redis trong AWX

Nếu gặp lỗi `ModuleNotFoundError: No module named 'redis'`:

**Option 1: Sử dụng requirements.txt trong Project**
- Thêm file `requirements.txt` vào project với nội dung: `redis>=4.0.0`

**Option 2: Cài đặt thủ công trong runner container**
```bash
# Tìm AWX runner pod
kubectl get pods -n awx | grep runner

# Cài đặt redis module
kubectl exec -n awx <awx-runner-pod> -- pip install redis
```

**Option 3: Cập nhật AWX image để bao gồm redis**
- Tạo custom AWX image với redis module đã được cài đặt

Xem chi tiết trong các script và file hướng dẫn.
