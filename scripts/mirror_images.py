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
import subprocess
import sys

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


def full_dst(reg, ns, dst):
    return f"{reg}/{ns}/{dst}"


def digest(ref):
    r = subprocess.run(
        ["skopeo", "inspect", "--format", "{{.Digest}}", f"docker://{ref}"],
        capture_output=True, text=True,
    )
    return r.stdout.strip() if r.returncode == 0 else None


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
        if i["dst"] in seen:
            print(f"FAIL dst 重复: {i['dst']}"); bad += 1
        seen.add(i["dst"])
    print("LINT-OK" if not bad else "LINT-FAIL")
    sys.exit(1 if bad else 0)


def verify():
    reg, ns, imgs = load()
    bad = 0
    for i in imgs:
        dst = full_dst(reg, ns, i["dst"])
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
        sd = digest(i["src"])
        dd = digest(full_dst(reg, ns, i["dst"]))
        if sd and sd == dd:
            print(f"SKIP {i['dst']} (digest 一致 {sd})")
            continue
        src = "docker://" + i["src"]
        dst = "docker://" + full_dst(reg, ns, i["dst"])
        print(f"COPY {i['src']} -> {full_dst(reg, ns, i['dst'])}")
        r = subprocess.run(["skopeo", "copy", "--all", "--retry-times", "3", src, dst])
        if r.returncode != 0:
            print(f"FAIL {i['dst']}"); fail += 1
        else:
            print(f"SYNCED {i['dst']} @ {digest(full_dst(reg, ns, i['dst']))}")
    print("SYNC-OK" if not fail else "SYNC-FAIL")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["lint", "verify", "sync"])
    a = ap.parse_args()
    {"lint": lint, "verify": verify, "sync": sync}[a.cmd]()
