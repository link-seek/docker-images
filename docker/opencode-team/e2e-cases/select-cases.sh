#!/bin/bash
# docker/opencode-team/e2e-cases/select-cases.sh — deterministic 选单（Jev 已退役，#505）。
#
# 用例零登记：e2e-cases/case-<id>.sh 头注释即元数据（CASE-ID/CASE-DESC/CASE-COST/CASE-SUGGEST），
# 本脚本启动即扫描组装名单+校验（id 与文件名不符/缺 DESC/COST 非法直接 fail）。
# smoke 为内置兜底，不需要文件。
#
# 输入（env）：
#   E2E_CASES   skip=一个不跑；full/all/空=全跑（默认全量）；名单=跑指定的。
# 输出：stdout 一行空格分隔的用例 id；详情打 stderr 进 run 日志。
# 约定：未知用例名直接 fail。deterministic，无模型调用。
set -uo pipefail

CASES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v python3 >/dev/null || { echo "FAIL: 缺 python3"; exit 1; }

# --- 自动发现：只扫 case-*.sh（helper/手册一律不算用例，避免误扫） ---
DISCOVERED="$(mktemp)"; RAWLIST=""; trap 'rm -f "$DISCOVERED" $RAWLIST' EXIT
dup_check="$(ls "$CASES_DIR"/case-*.sh 2>/dev/null || true)"
if [ -z "$dup_check" ]; then
  echo "select: e2e-cases/ 下无用例文件，只有内置 smoke 可用" >&2
fi
# 注意：循环体不用管道（子 shell 里 exit 只退子 shell，主流程拦不住），先写临时文件再 sort。
RAWLIST="$(mktemp)"
for f in $dup_check; do
  id="$(basename "$f" .sh)"
  cid="$(grep -m1 '^# CASE-ID:' "$f" | sed 's/^# CASE-ID:[[:space:]]*//')"
  desc="$(grep -m1 '^# CASE-DESC:' "$f" | sed 's/^# CASE-DESC:[[:space:]]*//')"
  cost="$(grep -m1 '^# CASE-COST:' "$f" | sed 's/^# CASE-COST:[[:space:]]*//')"
  [ "$cid" = "$id" ] || { echo "FAIL: $f 的 CASE-ID($cid) 与文件名($id)不一致"; exit 1; }
  [ -n "$desc" ] || { echo "FAIL: $f 缺 CASE-DESC"; exit 1; }
  case "$cost" in low|medium|high) ;; *) echo "FAIL: $f 的 CASE-COST($cost) 非法，只认 low/medium/high"; exit 1;; esac
  echo "$id" >> "$RAWLIST"
done
sort "$RAWLIST" > "$DISCOVERED"; rm -f "$RAWLIST"
if [ "$(sort "$DISCOVERED" | uniq -d | wc -l)" -ne 0 ]; then
  echo "FAIL: 用例 id 重复: $(sort "$DISCOVERED" | uniq -d | tr '\n' ' ')"; exit 1
fi
KNOWN="smoke $(tr '\n' ' ' < "$DISCOVERED")"

# 0) skip=一个不跑
if [ "${E2E_CASES:-}" = "skip" ]; then
  echo "select: explicitly skipped, no cases" >&2
  exit 0
fi

# 1) 空/full/all=全跑（默认全量）；名单=跑指定的
KNOWN="$KNOWN" WANT="${E2E_CASES:-full}" python3 - <<'PY'
import os, sys
known = set(os.environ["KNOWN"].split())
want = os.environ["WANT"].strip()
if want in ("", "all", "full", "auto"):
    print(" ".join(["smoke"] + sorted(known - {"smoke"})))
    sys.exit(0)
picked = [w.strip() for w in want.split(",") if w.strip()]
unknown = [w for w in picked if w not in known]
if unknown:
    print(f"FAIL: 未知用例: {','.join(unknown)}；当前可用: {','.join(sorted(known))}", file=sys.stderr)
    sys.exit(1)
print(" ".join(picked))
PY
