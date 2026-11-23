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
    if violations:
        print("POLICY-VIOLATIONS")
        for v in violations:
            print("  -", v)
        return 1
    print(f"POLICY-OK ({len(targets)} kustomizations)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
