#!/usr/bin/env python3
import json, os, redis
r = redis.Redis(host='172.17.196.126', port=6379, db=6, decode_responses=True)

def main():
    hosts = r.smembers("ansible:hosts") or []
    inv = {"_meta": {"hostvars": {}}}
    for h in hosts:
        inv["_meta"]["hostvars"][h] = r.hgetall(f"ansible:facts:{h}") or {}
    inv["all"] = {"hosts": list(hosts)}
    print(json.dumps(inv))

if __name__ == "__main__":
    main()