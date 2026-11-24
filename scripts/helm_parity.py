#!/usr/bin/env python3
"""Helm chart 与现有 kustomize 渲染的字段级 parity（#317 Phase 2）。

对每个实例：kubectl kustomize <dir> vs helm template charts/opencode -f values-<inst>.yaml，
按 (kind, namespace, name) 比较对象深相等（排除 Namespace）。
环境可覆盖：KUBECTL / HELM。
"""
import json
import os
import subprocess
import sys

import yaml

KUBECTL = os.environ.get("KUBECTL", "kubectl")
HELM = os.environ.get("HELM", "helm")

INST = {
    "team": ("k8s/opencode-team", "opencode-team"),
    "xieyucheng": ("k8s/opencode-xieyucheng", "opencode-xieyucheng"),
    "yingxin": ("k8s/opencode-yingxin", "opencode-yingxin"),
}


def load(text):
    return [d for d in yaml.safe_load_all(text) if d]


def norm(docs):
    out = {}
    for d in docs:
        if d.get("kind") == "Namespace":
            continue
        md = d.get("metadata", {})
        md.pop("creationTimestamp", None)
        d.pop("status", None)
        out[(d.get("kind"), md.get("namespace"), md.get("name"))] = d
    return out


def main() -> int:
    ok = True
    for inst, (path, ns) in INST.items():
        r = subprocess.run([KUBECTL, "kustomize", path], capture_output=True, text=True)
        if r.returncode != 0:
            print(f"[{inst}] kustomize FAIL: {r.stderr[-300:]}")
            ok = False
            continue
        h = subprocess.run(
            [HELM, "template", "opencode", "charts/opencode", "-n", ns,
             "-f", f"charts/opencode/values-{inst}.yaml"],
            capture_output=True, text=True,
        )
        if h.returncode != 0:
            print(f"[{inst}] helm FAIL: {h.stderr[-300:]}")
            ok = False
            continue
        a, b = norm(load(r.stdout)), norm(load(h.stdout))
        if set(a) != set(b):
            print(f"[{inst}] keys differ: only-kustomize={set(a)-set(b)} only-helm={set(b)-set(a)}")
            ok = False
            continue
        diffs = [k for k in a if json.dumps(a[k], sort_keys=True, default=str) !=
                 json.dumps(b[k], sort_keys=True, default=str)]
        if diffs:
            print(f"[{inst}] value diffs: {diffs}")
            for k in diffs[:2]:
                print("  base:", json.dumps(a[k], sort_keys=True)[:200])
                print("  helm:", json.dumps(b[k], sort_keys=True)[:200])
            ok = False
        else:
            print(f"[{inst}] PARITY-OK ({len(a)} objects)")
    print("ALL-PARITY-OK" if ok else "PARITY-FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
