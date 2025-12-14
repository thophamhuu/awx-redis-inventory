# Giải quyết lỗi: ModuleNotFoundError: No module named 'redis'

## Lỗi
```
ModuleNotFoundError: No module named 'redis'
```

## Giải pháp nhanh

### Cách 1: Cài đặt trực tiếp trong AWX runner (Nhanh nhất)

```bash
# Tìm AWX runner pod
kubectl get pods -n awx | grep runner

# Cài đặt redis module
kubectl exec -n awx <awx-runner-pod-name> -- pip install redis

# Hoặc nếu có nhiều runner pods
kubectl get pods -n awx -l app.kubernetes.io/component=awx-runner -o name | \
  xargs -I {} kubectl exec -n awx {} -- pip install redis
```

### Cách 2: Sử dụng script tự động

```bash
cd awx-redis-inventory
./install-redis-module-awx.sh
```

### Cách 3: Thêm requirements.txt vào AWX Project

1. Vào AWX Web Interface
2. Projects > Chọn project chứa `redis_inventory.py`
3. Tab "Details" > Scroll xuống "Python Virtual Environment"
4. Thêm file `requirements.txt` với nội dung:
   ```
   redis>=4.0.0
   ```
5. Save và sync lại project

### Cách 4: Tạo custom AWX image (Lâu dài)

Tạo Dockerfile:
```dockerfile
FROM quay.io/ansible/awx-ee:latest
RUN pip install redis>=4.0.0
```

Build và push image, sau đó cập nhật AWX settings để sử dụng image này.

## Kiểm tra sau khi cài đặt

```bash
# Kiểm tra module đã được cài đặt
kubectl exec -n awx <awx-runner-pod-name> -- python3 -c "import redis; print(redis.__version__)"
```

## Lưu ý

- Nếu có nhiều runner pods, cần cài đặt cho tất cả
- Cài đặt sẽ mất khi pod restart (trừ khi dùng custom image hoặc requirements.txt)
- Khuyến nghị: Sử dụng requirements.txt trong AWX Project để tự động cài đặt

