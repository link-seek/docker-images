#!/usr/bin/env python3
"""声明式镜像同步：读 images/mirror.yaml，在 GitHub runner 上把上游镜像复制进 SWR。

子命令：
  lint    校验清单结构（src/dst 带 tag、禁 latest）——PR 门用，不连网
  verify  检查每个 dst 是否已在 SWR（漂移检测）——定时任务用
  sync    把缺的/不一致的镜像 copy 到 SWR（保多架构/摘要）——合 main 后用

执行者必须对上游（docker.io 等）有干净出口；不要在集群内跑（集群连上游不稳）。
凭据：先 `skopeo login $REG`，本脚本不接触密码。
"""
import argparse
import datetime
import hashlib
import hmac
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

import yaml

MANIFEST = "images/mirror.yaml"


def load():
    d = yaml.safe_load(open(MANIFEST))
    reg = d["registry"]
    ns = d["namespace"]
    imgs = d["images"] or []
    if not reg or not ns:
        sys.exit("FAIL: registry/namespace 必填")
    return reg, ns, imgs


def item_ns(item, default_ns):
    # 单条可用 ns: 覆盖顶层 namespace（组织配额满时用个人空间，如 xieyucheng123）
    ns = item.get("ns") or default_ns
    if not ns:
        sys.exit(f"FAIL: 条目缺 ns 且顶层无默认: {item}")
    return ns


def full_dst(reg, ns, dst):
    return f"{reg}/{ns}/{dst}"


def repo_of(dst: str) -> str:
    return dst.rsplit(":", 1)[0]


def item_dst(reg, default_ns, item):
    return full_dst(reg, item_ns(item, default_ns), item["dst"])


def digest(ref):
    r = subprocess.run(
        ["skopeo", "inspect", "--format", "{{.Digest}}", f"docker://{ref}"],
        capture_output=True, text=True,
    )
    return r.stdout.strip() if r.returncode == 0 else None


def make_public(ns: str, repo: str) -> None:
    """把 SWR 仓库设为公开（集群匿名拉取）；幂等，缺 AK/SK 时跳过。"""
    ak = os.environ.get("PROD_HCLOUD_AK", "").strip()
    sk = os.environ.get("PROD_HCLOUD_SK", "").strip()
    if not ak or not sk:
        print(f"SKIP make-public {ns}/{repo} (no AK/SK)")
        return
    host = "swr-api.cn-north-9.myhuaweicloud.com"
    path = f"/v2/manage/namespaces/{ns}/repos/{repo}"
    body = json.dumps({"is_public": True}).encode()
    now = datetime.datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    payload = hashlib.sha256(body).hexdigest()
    canon_headers = f"host:{host}\nx-sdk-date:{now}\n"
    signed = "host;x-sdk-date"
    canon = f"PATCH\n{path}/\n\n{canon_headers}\n{signed}\n{payload}"  # SWR canonical URI 带尾斜杠
    sts = f"SDK-HMAC-SHA256\n{now}\n{hashlib.sha256(canon.encode()).hexdigest()}"
    sig = hmac.new(sk.encode(), sts.encode(), hashlib.sha256).hexdigest()
    req = urllib.request.Request(
        "https://" + host + path,
        data=body,
        method="PATCH",
        headers={
            "Host": host,
            "X-Sdk-Date": now,
            "Content-Type": "application/json",
            "Authorization": f"SDK-HMAC-SHA256 Access={ak}, SignedHeaders={signed}, Signature={sig}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            print(f"PUBLIC {ns}/{repo}: {r.status}")
    except urllib.error.HTTPError as e:
        print(f"WARN make-public {ns}/{repo}: HTTP {e.code} {e.read().decode()[:120]}")


def lint():
    reg, ns, imgs = load()
    bad = 0
    seen = set()
    for i in imgs:
        if "src" not in i or "dst" not in i:
            print(f"FAIL 条目缺 src/dst: {i}"); bad += 1; continue
        for k in ("src", "dst"):
            ref = i[k]
            if ":" not in ref.split("/")[-1]:
                print(f"FAIL {k} 未带 tag: {ref}"); bad += 1
            if ref.endswith(":latest"):
                print(f"FAIL {k} 禁 latest: {ref}"); bad += 1
        key = (item_ns(i, ns), i["dst"])
        if key in seen:
            print(f"FAIL dst 重复: {key}"); bad += 1
        seen.add(key)
    print("LINT-OK" if not bad else "LINT-FAIL")
    sys.exit(1 if bad else 0)


def verify():
    reg, ns, imgs = load()
    bad = 0
    for i in imgs:
        dst = item_dst(reg, ns, i)
        dg = digest(dst)
        if not dg:
            print(f"MISSING {dst}"); bad += 1
        else:
            print(f"OK {dst} @ {dg}")
    print("VERIFY-OK" if not bad else "VERIFY-FAIL")
    sys.exit(1 if bad else 0)


def sync():
    reg, ns, imgs = load()
    fail = 0
    for i in imgs:
        dst = item_dst(reg, ns, i)
        sd = digest(i["src"])
        dd = digest(dst)
        if sd and sd == dd:
            print(f"SKIP {i['dst']} (digest 一致 {sd})")
            make_public(item_ns(i, ns), repo_of(i["dst"]))
            continue
        src = "docker://" + i["src"]
        print(f"COPY {i['src']} -> {dst}")
        r = subprocess.run(["skopeo", "copy", "--all", "--retry-times", "3", src, "docker://" + dst])
        if r.returncode != 0:
            print(f"FAIL {i['dst']}"); fail += 1
        else:
            print(f"SYNCED {i['dst']} @ {digest(dst)}")
            make_public(item_ns(i, ns), repo_of(i["dst"]))
    print("SYNC-OK" if not fail else "SYNC-FAIL")
    sys.exit(1 if fail else 0)


def make_public_all():
    reg, ns, imgs = load()
    for i in imgs:
        make_public(item_ns(i, ns), repo_of(i["dst"]))
    print("MAKE-PUBLIC-OK")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["lint", "verify", "sync", "make-public"])
    a = ap.parse_args()
    {"lint": lint, "verify": verify, "sync": sync, "make-public": make_public_all}[a.cmd]()
