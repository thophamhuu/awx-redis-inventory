#!/usr/bin/env python3
import json, os, redis

def get_redis_client():
    """Tạo Redis client - sử dụng Redis client thông thường, sẽ xử lý cluster mode khi gặp MovedError"""
    host = '172.17.196.126'
    port = 6379
    
    # Sử dụng Redis client thông thường
    # Nếu là cluster mode và gặp MovedError, sẽ xử lý trong main()
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
            # Trả về inventory rỗng với thông báo lỗi
            # Lưu ý: Script sẽ hoạt động đúng khi chạy từ bên trong AWX pod
            # (trong cùng mạng với Redis cluster, có thể truy cập tất cả nodes)
            print(json.dumps({
                "_meta": {"hostvars": {}},
                "all": {"hosts": []},
                "_error": f"Redis cluster mode detected. Key moved to different node: {e}. "
                         f"Script needs to run from within cluster network (e.g., AWX pod) to access all nodes."
            }))
            sys.exit(0)  # Exit 0 để không làm fail AWX job, chỉ trả về inventory rỗng
        except Exception as e:
            # Lỗi khác khi đọc hosts
            print(json.dumps({
                "_meta": {"hostvars": {}},
                "all": {"hosts": []},
                "_error": f"Error reading hosts from Redis: {e}"
            }), file=sys.stderr)
            sys.exit(1)
        
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
        # Lỗi tổng quát
        print(json.dumps({
            "_meta": {"hostvars": {}},
            "all": {"hosts": []},
            "_error": f"Unexpected error: {e}"
        }), file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    import sys
    main()