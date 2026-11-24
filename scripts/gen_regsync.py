#!/usr/bin/env python3
"""从 images/mirror.yaml 生成 regsync 配置（stdout）。#317 adopt-list：regsync 接管同步。

凭据从 env SWR_LOGIN_USER / SWR_LOGIN_PASS 注入（仅 target SWR 需要；source 匿名）。
"""
import os
import sys

import yaml


def main() -> int:
    d = yaml.safe_load(open("images/mirror.yaml"))
    reg, ns = d["registry"], d["namespace"]
    imgs = d.get("images") or []
    sync = []
    for i in imgs:
        n = i.get("ns") or ns
        sync.append({
            "source": i["src"],
            "target": f"{reg}/{n}/{i['dst']}",
            "type": "image",
        })
    cfg = {"version": 1, "sync": sync}
    user = os.environ.get("SWR_LOGIN_USER", "").strip()
    pwd = os.environ.get("SWR_LOGIN_PASS", "").strip()
    if user and pwd:
        # 用 regsync 官方支持的 env 模板，避免把密码写进文件。
        cfg["creds"] = [{
            "registry": reg,
            "user": '{{env "SWR_LOGIN_USER"}}',
            "pass": '{{env "SWR_LOGIN_PASS"}}',
        }]
    sys.stdout.write(yaml.safe_dump(cfg, sort_keys=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
