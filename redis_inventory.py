#!/usr/bin/env python3
import json, os, sys

# Thêm /tmp/redis-packages vào PYTHONPATH nếu có
if os.path.exists('/tmp/redis-packages'):
    sys.path.insert(0, '/tmp/redis-packages')

import redis

def get_redis_client():
    """Tạo Redis client - thử cluster mode trước, nếu không phải thì dùng Redis thông thường"""
    host = '172.17.196.126'
    port = 6379
    
    # Thử sử dụng Redis Cluster client trước
    try:
        from redis.cluster import RedisCluster
        startup_nodes = [{"host": host, "port": port}]
        r = RedisCluster(startup_nodes=startup_nodes, decode_responses=True, socket_connect_timeout=5, skip_full_coverage_check=True)
        # Test connection
        r.ping()
        return r
    except (ImportError, redis.exceptions.RedisError, Exception):
        # Nếu không phải cluster hoặc không có cluster client, dùng Redis thông thường
        r = redis.Redis(host=host, port=port, decode_responses=True, socket_connect_timeout=5)
        return r

def main():
    try:
        r = get_redis_client()
        
        # Đọc hosts từ Redis
        try:
            hosts = r.smembers("ansible:hosts") or []
        except redis.exceptions.MovedError as e:
            # Xử lý MovedError - key được chuyển đến node khác trong cluster
            # Thử lại với Redis Cluster client
            print(f"Redis MovedError detected: {e}. Retrying with cluster client...", file=sys.stderr)
            try:
                from redis.cluster import RedisCluster
                startup_nodes = [{"host": "172.17.196.126", "port": 6379}]
                r = RedisCluster(startup_nodes=startup_nodes, decode_responses=True, socket_connect_timeout=5, skip_full_coverage_check=True)
                hosts = r.smembers("ansible:hosts") or []
            except Exception as cluster_error:
                # Nếu vẫn lỗi, trả về inventory rỗng (không có _error group)
                print(f"Failed to connect to Redis cluster: {cluster_error}", file=sys.stderr)
                print(json.dumps({
                    "_meta": {"hostvars": {}},
                    "all": {"hosts": []}
                }))
                sys.exit(0)  # Exit 0 để không làm fail AWX job
        except Exception as e:
            # Lỗi khác khi đọc hosts - log ra stderr, trả về inventory rỗng
            print(f"Error reading hosts from Redis: {e}", file=sys.stderr)
            print(json.dumps({
                "_meta": {"hostvars": {}},
                "all": {"hosts": []}
            }))
            sys.exit(0)  # Exit 0 để không làm fail AWX job
        
        # Tạo inventory structure
        inv = {"_meta": {"hostvars": {}}}
        
        # Đọc facts cho từng host
        for h in hosts:
            try:
                facts = r.hgetall(f"ansible:facts:{h}") or {}
                inv["_meta"]["hostvars"][h] = facts
            except redis.exceptions.MovedError:
                # Nếu facts key được chuyển, bỏ qua facts cho host này
                inv["_meta"]["hostvars"][h] = {}
            except Exception:
                # Lỗi khác, vẫn thêm host nhưng không có facts
                inv["_meta"]["hostvars"][h] = {}
        
        inv["all"] = {"hosts": list(hosts)}
        
        # Output JSON
        print(json.dumps(inv))
        
    except Exception as e:
        # Lỗi tổng quát - log ra stderr, trả về inventory rỗng
        print(f"Unexpected error: {e}", file=sys.stderr)
        print(json.dumps({
            "_meta": {"hostvars": {}},
            "all": {"hosts": []}
        }))
        sys.exit(0)  # Exit 0 để không làm fail AWX job

if __name__ == "__main__":
    import sys
    main()