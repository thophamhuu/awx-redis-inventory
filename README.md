# AWX Redis Inventory

Dự án này cung cấp giải pháp tích hợp Redis làm nguồn inventory động cho AWX (Ansible Tower). Script `redis_inventory.py` đọc danh sách hosts và facts từ Redis và trả về định dạng JSON inventory chuẩn của Ansible.

## Tổng Quan

AWX Redis Inventory cho phép bạn:
- Lưu trữ inventory động trong Redis
- Hỗ trợ cả Redis standalone và Redis Cluster
- Tự động đồng bộ hosts và facts từ Redis vào AWX
- Sử dụng custom Docker images với Redis package đã được cài đặt sẵn

## Kiến Trúc

### Cấu Trúc Dữ Liệu trong Redis

Script sử dụng các keys sau trong Redis:

- `ansible:hosts` (Set): Chứa danh sách tất cả hostnames
- `ansible:facts:{hostname}` (Hash): Chứa facts/variables cho từng host

**Ví dụ:**
```bash
# Thêm hosts vào Redis
redis-cli SADD ansible:hosts "web-server-01" "web-server-02" "db-server-01"

# Thêm facts cho host
redis-cli HMSET ansible:facts:web-server-01 ansible_host "192.168.1.10" ansible_user "admin" group "webservers"
```

### Output Format

Script trả về JSON inventory theo chuẩn Ansible:
```json
{
  "_meta": {
    "hostvars": {
      "web-server-01": {
        "ansible_host": "192.168.1.10",
        "ansible_user": "admin",
        "group": "webservers"
      }
    }
  },
  "all": {
    "hosts": ["web-server-01", "web-server-02", "db-server-01"]
  }
}
```

## Cài Đặt

### Yêu Cầu

- AWX 24.6.1 hoặc mới hơn
- Docker (để build custom images)
- kubectl (nếu dùng K3s/Kubernetes)
- AWX CLI (để tự động hóa cấu hình)

### Cách 1: Sử Dụng Custom AWX Image (Khuyến Nghị)

Script này sẽ build custom AWX image với Redis package và cập nhật AWX instance:

```bash
./setup-permanent-redis.sh
```

Script này sẽ:
1. Kiểm tra và cài đặt Docker nếu cần
2. Build custom AWX image với Redis package
3. Export image cho K3s
4. Import image vào K3s
5. Backup AWX instance hiện tại
6. Cập nhật AWX instance với custom image

### Cách 2: Sử Dụng Execution Environment

Nếu bạn chỉ cần Redis cho inventory sources (không cần cho AWX task), sử dụng Execution Environment:

#### Bước 1: Build AWX-EE Image

```bash
./build-awx-ee-image.sh
```

#### Bước 2: Tạo Execution Environment trong AWX

```bash
./setup-execution-environment.sh
```

Hoặc thủ công qua Web UI:
1. Vào: **Administration > Execution Environments**
2. Click **Add**
3. Điền thông tin:
   - Name: `awx-ee-redis`
   - Image: `awx-ee-custom:24.6.1-redis`
   - Pull: `Always` hoặc `If not present`
4. Click **Save**

#### Bước 3: Cập Nhật Inventory Source

```bash
./update-inventory-source-ee.sh
```

Hoặc thủ công:
1. Vào: **Inventories > [Your Inventory] > Sources > [Your Source]**
2. Trong tab **Details**, tìm **Execution Environment**
3. Chọn: `awx-ee-redis`
4. Click **Save**

## Cấu Hình

### Cấu Hình Redis Connection

Mặc định, script kết nối đến Redis tại:
- Host: `172.17.196.126`
- Port: `6379`

Để thay đổi, chỉnh sửa trong `redis_inventory.py`:

```python
def get_redis_client():
    host = 'YOUR_REDIS_HOST'  # Thay đổi ở đây
    port = 6379                # Thay đổi port nếu cần
    # ...
```

### Cấu Hình Inventory Source trong AWX

1. Tạo Inventory mới hoặc chọn inventory có sẵn
2. Vào tab **Sources**, click **Add**
3. Điền thông tin:
   - **Name**: Tên source (ví dụ: "Redis Inventory")
   - **Source**: `Custom Script`
   - **Custom Inventory Script**: Chọn hoặc upload `redis_inventory.py`
   - **Execution Environment**: Chọn `awx-ee-redis` (nếu dùng EE)
4. Click **Save**
5. Click **Sync** để test

## Sử Dụng

### Cập Nhật Script trong AWX Project

Nếu script được lưu trong AWX project, bạn có thể cập nhật nhanh:

```bash
./update-redis-inventory-script.sh
```

**Lưu ý**: Script này sẽ bị ghi đè khi project được sync lại. Để cập nhật vĩnh viễn, hãy cập nhật script trong Git repository của AWX project.

### Thêm Hosts vào Redis

```bash
# Kết nối Redis
redis-cli -h 172.17.196.126 -p 6379

# Thêm host vào danh sách
SADD ansible:hosts "new-server-01"

# Thêm facts cho host
HMSET ansible:facts:new-server-01 \
  ansible_host "192.168.1.100" \
  ansible_user "admin" \
  ansible_ssh_private_key_file "/path/to/key" \
  group "webservers"
```

### Xóa Hosts khỏi Redis

```bash
# Xóa host khỏi danh sách
SREM ansible:hosts "old-server-01"

# Xóa facts của host
DEL ansible:facts:old-server-01
```

### Đồng Bộ Inventory trong AWX

Sau khi cập nhật Redis, đồng bộ inventory trong AWX:
- Qua Web UI: Vào Inventory Source, click **Sync**
- Qua CLI: `awx inventory_sources sync <source-id>`

## Xử Lý Lỗi

Script được thiết kế để xử lý lỗi một cách graceful:

- **Lỗi kết nối Redis**: Trả về inventory rỗng, không làm fail AWX job
- **Lỗi Redis Cluster (MovedError)**: Tự động retry với RedisCluster client
- **Lỗi đọc facts**: Host vẫn được thêm vào inventory nhưng không có facts

Tất cả lỗi được log ra `stderr` để debug.

## Files trong Dự Án

| File | Mô Tả |
|------|-------|
| `redis_inventory.py` | Script Python chính để đọc inventory từ Redis |
| `requirements.txt` | Python dependencies (redis>=4.0.0) |
| `Dockerfile` | Dockerfile để build custom AWX image |
| `Dockerfile.ee` | Dockerfile để build custom AWX-EE image |
| `build-awx-image.sh` | Script build AWX image với Redis |
| `build-awx-ee-image.sh` | Script build AWX-EE image với Redis |
| `setup-permanent-redis.sh` | Script tự động setup Redis package vĩnh viễn |
| `setup-execution-environment.sh` | Script tạo/cập nhật Execution Environment |
| `update-inventory-source-ee.sh` | Script cập nhật Inventory Source |
| `update-redis-inventory-script.sh` | Script cập nhật redis_inventory.py trong AWX |

## Troubleshooting

### Kiểm Tra Redis Package trong AWX

```bash
# Lấy pod name
POD_NAME=$(kubectl get pods -n awx -l app.kubernetes.io/name=awx,app.kubernetes.io/component=awx-task -o jsonpath='{.items[0].metadata.name}')

# Kiểm tra Redis package
kubectl exec -n awx $POD_NAME -c awx-task -- python3 -c "import redis; print(f'Redis version: {redis.__version__}')"
```

### Kiểm Tra Kết Nối Redis

```bash
# Test kết nối từ AWX pod
kubectl exec -n awx $POD_NAME -c awx-task -- python3 -c "import redis; r = redis.Redis(host='172.17.196.126', port=6379, decode_responses=True); print(r.ping())"
```

### Xem Logs

```bash
# Xem logs của AWX task
kubectl logs -n awx -l app.kubernetes.io/name=awx,app.kubernetes.io/component=awx-task -f

# Xem logs của inventory sync job
# Vào AWX Web UI > Jobs > [Inventory Sync Job] > Output
```

### Rollback

Nếu cần rollback về image gốc:

```bash
kubectl patch awx awx -n awx --type merge -p '{"spec":{"image":"quay.io/ansible/awx:24.6.1"}}'
```

## Phát Triển

### Cấu Trúc Code

- `get_redis_client()`: Tạo Redis client, tự động detect Redis Cluster
- `main()`: Hàm chính đọc hosts và facts từ Redis, trả về JSON inventory

### Mở Rộng

Để thêm tính năng mới (ví dụ: groups, hostvars phức tạp hơn), chỉnh sửa `redis_inventory.py`:

```python
# Ví dụ: Thêm groups từ Redis
groups = r.smembers("ansible:groups") or []
for group in groups:
    group_hosts = r.smembers(f"ansible:group:{group}") or []
    inv[group] = {"hosts": list(group_hosts)}
```

## License

Dự án này được phát triển cho mục đích tích hợp AWX với Redis.

## Tác Giả

Dự án được tạo để tích hợp Redis làm inventory source động cho AWX.

