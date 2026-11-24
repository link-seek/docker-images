#!/usr/bin/env python3
"""Release policy (audit -> enforce).

Checks, all against *rendered* output (kustomization images: overrides applied):
  1. every container image must be digest-pinned (@sha256:)
  2. no :latest reference
  3. kustomization.yaml images: entries must use digest:, not newTag:

Exit 1 on violations; the CI job runs this in audit mode (continue-on-error).
"""
import pathlib
import re
import subprocess
import sys

import yaml

ROOT = pathlib.Path(".").resolve()
SKIP_DIRS = {"_preflight"}


def render(path: pathlib.Path):
    for cmd in (["kubectl", "kustomize", str(path)], ["kustomize", "build", str(path)]):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        except FileNotFoundError:
            continue
        if r.returncode == 0:
            return r.stdout, None
        last = r.stderr.strip().splitlines()[-1:] or [r.stderr.strip()]
        return None, last[0]
    return None, "no kustomize/kubectl available"


def walk_images(node, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "image" and isinstance(v, str):
                out.append(v)
            else:
                walk_images(v, out)
    elif isinstance(node, list):
        for v in node:
            walk_images(v, out)


def check_bake_verification(violations):
    """item1: 每个 bake-stack caller 必须声明 verification=full|upstream；
    upstream 必须带 reason + 未过期 exp（沿用 .trivyignore 的 exp 记法）。"""
    import datetime

    wf = ROOT / ".github" / "workflows"
    if not wf.is_dir():
        return
    today = datetime.date.today()
    callers = 0
    for f in sorted(wf.glob("bake-*.yml")):
        if f.name == "bake-stack.yml":
            continue
        try:
            doc = yaml.safe_load(f.read_text()) or {}
        except Exception as e:  # noqa: BLE001
            violations.append(f"{f.name}: yaml parse failed: {e}")
            continue
        for _jid, job in (doc.get("jobs") or {}).items():
            if not isinstance(job, dict):
                continue
            if job.get("uses") != "./.github/workflows/bake-stack.yml":
                continue
            callers += 1
            w = job.get("with") or {}
            v = str(w.get("verification", "")).strip()
            if v not in ("full", "upstream"):
                violations.append(
                    f"{f.name}: bake caller verification 缺/非法（须 full|upstream，实际='{v}'）"
                )
                continue
            if v == "upstream":
                r = str(w.get("verification_reason", "")).strip()
                e = str(w.get("verification_exp", "")).strip()
                if not r:
                    violations.append(f"{f.name}: verification=upstream 缺 verification_reason")
                if not re.match(r"^\d{4}-\d{2}-\d{2}$", e):
                    violations.append(
                        f"{f.name}: verification=upstream 缺/非法 verification_exp='{e}'"
                    )
                else:
                    try:
                        if datetime.date.fromisoformat(e) < today:
                            violations.append(
                                f"{f.name}: verification=upstream 已过期 exp={e} (< {today})"
                            )
                    except ValueError:
                        violations.append(f"{f.name}: verification_exp 无法解析 '{e}'")
    if callers == 0:
        violations.append("未发现任何 bake-stack caller（检查 .github/workflows/bake-*.yml 路径）")


def check_dockerfile_pins(violations):
    """item2: docker/*/Dockerfile 的 FROM 必须 @sha256: 固定。
    例外：紧邻上一行写 `# digest-exempt: <理由> [exp:YYYY-MM-DD]`（过期即红；builder/内部派生 base 用）。"""
    import datetime

    today = datetime.date.today()
    docker_dir = ROOT / "docker"
    if not docker_dir.is_dir():
        return
    for f in sorted(docker_dir.glob("*/Dockerfile")):
        pending = None
        for ln, raw in enumerate(f.read_text().splitlines(), 1):
            s = raw.strip()
            if s.startswith("#") and "digest-exempt:" in s:
                pending = s
                continue
            if not s or s.startswith("#"):
                continue
            if s.upper().startswith("FROM "):
                if "@sha256:" in s or "scratch" in s.lower():
                    pending = None
                    continue
                if pending:
                    em = re.search(r"exp:(\d{4}-\d{2}-\d{2})", pending)
                    if em:
                        try:
                            if datetime.date.fromisoformat(em.group(1)) < today:
                                violations.append(
                                    f"{f.relative_to(ROOT)}:{ln}: digest-exempt 已过期 exp={em.group(1)} -> {s}"
                                )
                        except ValueError:
                            violations.append(
                                f"{f.relative_to(ROOT)}:{ln}: digest-exempt exp 非法 '{em.group(1)}'"
                            )
                    pending = None
                    continue
                violations.append(
                    f"{f.relative_to(ROOT)}:{ln}: FROM 未 digest pin（缺 @sha256:，且无紧邻 digest-exempt）-> {s}"
                )
            else:
                pending = None


def main():
    violations = []
    targets = [p for p in sorted((ROOT / "k8s").iterdir()) if p.is_dir() and p.name not in SKIP_DIRS]
    for d in targets:
        kfile = d / "kustomization.yaml"
        if not kfile.exists():
            continue
        rendered, err = render(d)
        if rendered is None:
            violations.append(f"{d.name}: render failed: {err}")
            continue
        try:
            docs = list(yaml.safe_load_all(rendered))
        except Exception as e:  # noqa: BLE001
            violations.append(f"{d.name}: yaml parse failed: {e}")
            continue
        images = []
        for doc in docs:
            if isinstance(doc, dict):
                walk_images(doc, images)
        for img in images:
            if ":latest" in img:
                violations.append(f"{d.name}: uses :latest -> {img}")
            if "@sha256:" not in img:
                violations.append(f"{d.name}: not digest-pinned -> {img}")
        # kustomization images: must be digest-based
        try:
            k = yaml.safe_load(kfile.read_text()) or {}
        except Exception:
            k = {}
        for entry in k.get("images") or []:
            if "newTag" in entry and "digest" not in entry:
                violations.append(f"{d.name}/kustomization.yaml: images[].newTag without digest -> {entry}")
    check_bake_verification(violations)
    check_dockerfile_pins(violations)
    if violations:
        print("POLICY-VIOLATIONS")
        for v in violations:
            print("  -", v)
        return 1
    print(f"POLICY-OK ({len(targets)} kustomizations)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
