#!/usr/bin/env python3
"""发布后可拉验证（#317 阶段二-5）。

子命令：
  anon <ref>         匿名拉（registry token 流程，不带任何凭据）——验证 public 镜像可被集群匿名拉
  anon-file <yaml>   对 images/mirror.yaml 的每个 dst 做匿名校验
  auth <ref>         认证拉（依赖当前已 docker login；用 docker manifest/imagetools 探 manifest）

ref 形如 swr.cn-north-9.myhuaweicloud.com/link-seek/opencode-team:2.3.0
失败退出码 1（让流水线整单红）。
"""
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request

ACCEPT = ",".join([
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
])


def split_ref(ref):
    reg, rest = ref.split("/", 1)
    last = rest.split("/")[-1]
    if ":" in last:
        repo, tag = rest.rsplit(":", 1)
    else:
        repo, tag = rest, "latest"
    return reg, repo, tag


def _get(url, headers):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=45) as r:
        return r.status, r.read()


def anon_manifest_ok(ref):
    reg, repo, tag = split_ref(ref)
    base = f"https://{reg}/v2/{repo}/manifests/{tag}"
    try:
        code, _ = _get(base, {"Accept": ACCEPT})
        return code == 200, f"manifest {code}"
    except urllib.error.HTTPError as e:
        if e.code != 401:
            return False, f"HTTP {e.code}"
        wa = e.headers.get("WWW-Authenticate", "")
        realm = re.search(r'realm="([^"]+)"', wa)
        service = re.search(r'service="([^"]+)"', wa)
        scope = re.search(r'scope="([^"]+)"', wa)
        if not realm:
            return False, f"401 无 realm: {wa[:80]}"
        tok_url = realm.group(1)
        params = []
        if service:
            params.append("service=" + service.group(1))
        if scope:
            params.append("scope=" + scope.group(1))
        if params:
            tok_url += ("&" if "?" in tok_url else "?") + "&".join(params)
        try:
            _, body = _get(tok_url, {})
            j = json.loads(body)
            tok = j.get("token") or j.get("access_token")
        except Exception as ex:  # noqa: BLE001
            return False, f"匿名 token 失败: {ex}"
        if not tok:
            return False, "匿名 token 为空"
        try:
            code, _ = _get(base, {"Accept": ACCEPT, "Authorization": "Bearer " + tok})
            return code == 200, f"manifest {code} (anon token)"
        except urllib.error.HTTPError as e2:
            return False, f"匿名 token 后 manifest HTTP {e2.code}"
    except Exception as ex:  # noqa: BLE001
        return False, f"连接失败: {ex}"


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
        import yaml  # 懒导入：auth/anon 单条不需要 pyyaml
        d = yaml.safe_load(open(sys.argv[2]))
        reg, ns = d["registry"], d["namespace"]
        bad = 0
        for i in d.get("images") or []:
            n = i.get("ns") or ns
            ref = f"{reg}/{n}/{i['dst']}"
            ok, msg = anon_manifest_ok(ref)
            print(("OK   " if ok else "FAIL ") + f"anon {ref} :: {msg}")
            bad += 0 if ok else 1
        print("ANON-PULL-OK" if not bad else "ANON-PULL-FAIL")
        return 0 if bad == 0 else 1
    fn = anon_manifest_ok if mode == "anon" else auth_ok
    ok, msg = fn(sys.argv[2])
    print(("OK   " if ok else "FAIL ") + f"{mode} {sys.argv[2]} :: {msg}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
