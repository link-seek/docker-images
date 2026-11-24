#!/usr/bin/env python3
"""发布后可拉验证（#317 Phase 1）：委托社区 regctl（regclient），不再自研 registry token 流。

  anon <ref>         匿名确认 manifest 可取（无凭据）
  anon-file <yaml>   对 images/mirror.yaml 的每个 dst 做匿名确认
  auth <ref>         认证确认（依赖已 docker login；用 docker manifest/inspect）

失败退出码 1（让流水线整单红）。
"""
import subprocess
import sys

import yaml


def regctl_ok(ref):
    try:
        r = subprocess.run(
            ["regctl", "manifest", "get", ref, "--format", "{{.GetDescriptor.Digest}}"],
            capture_output=True, text=True, timeout=90,
        )
        out = (r.stdout or "").strip()
        if r.returncode == 0 and out.startswith("sha256:"):
            return True, out[:19] + "…"
        err = (r.stderr or r.stdout or "").strip().splitlines()
        return False, err[-1][:160] if err else "regctl failed"
    except Exception as ex:  # noqa: BLE001
        return False, f"regctl err: {ex}"


def auth_ok(ref):
    err = ""
    for cmd in (["docker", "manifest", "inspect", ref],
                ["docker", "buildx", "imagetools", "inspect", ref]):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            if r.returncode == 0:
                return True, f"ok ({' '.join(cmd[1:3])})"
            out = (r.stderr or r.stdout).strip().splitlines()
            err = out[-1] if out else ""
        except Exception as ex:  # noqa: BLE001
            err = str(ex)
    return False, err


def main():
    if len(sys.argv) < 3:
        print("usage: verify_pull.py auth|anon|anon-file <ref|yaml>")
        return 2
    mode = sys.argv[1]
    if mode == "anon-file":
        d = yaml.safe_load(open(sys.argv[2]))
        reg, ns = d["registry"], d["namespace"]
        bad = 0
        for i in d.get("images") or []:
            n = i.get("ns") or ns
            ref = f"{reg}/{n}/{i['dst']}"
            ok, msg = regctl_ok(ref)
            print(("OK   " if ok else "FAIL ") + f"anon {ref} :: {msg}")
            bad += 0 if ok else 1
        print("ANON-PULL-OK" if not bad else "ANON-PULL-FAIL")
        return 0 if bad == 0 else 1
    fn = regctl_ok if mode == "anon" else auth_ok
    ok, msg = fn(sys.argv[2])
    print(("OK   " if ok else "FAIL ") + f"{mode} {sys.argv[2]} :: {msg}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
