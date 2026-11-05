#!/bin/bash
# docker/opencode-tools/e2e-cases/select-cases.sh — 用 Jev 选本次要跑的 E2E 用例。
#
# 用例零登记：e2e-cases/<id>.sh 头注释即元数据（CASE-ID/CASE-DESC/CASE-COST/CASE-SUGGEST），
# 本脚本启动即扫描组装名单+校验（id 与文件名不符/缺 DESC/COST 非法/重复 id 直接 fail）。
# smoke 为内置兜底，不需要文件。
#
# 输入（env）：
#   E2E_CASES   skip=一个不跑；full/all=全跑；名单=跑指定的；空=自动推断（调 Jev）。
#   BASE_REF    diff 起点（默认 HEAD~1；push 由流水线填 before）。如 "abc1234"。
#   HEAD_REF    diff 终点（默认 HEAD）。
#   JEV_THRESHOLD 选中阈值（默认 0.5）。
#   OPENCODE_API_KEY  Zen/Console key（走 Jev 路径时必填）。
# 输出：stdout 一行空格分隔的用例 id；详情打 stderr 进 run 日志。
# 约定：未知用例名直接 fail；Jev 不可用直接 fail（手动填名单重跑）。
# 密钥：不处理（secret-hygiene 另有门禁，diff 原样喂）。
set -uo pipefail

CASES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THRESHOLD="${JEV_THRESHOLD:-0.5}"
HEAD_REF="${HEAD_REF:-HEAD}"
JEV_URL="${JEV_URL:-https://opencode.ai/zen/v1/systemone}"
JEV_MODEL="${JEV_MODEL:-jev-1.13-free}"
DIFF_CAP="${DIFF_CAP_BYTES:-204800}"

command -v python3 >/dev/null || { echo "FAIL: 缺 python3"; exit 1; }

# --- 自动发现：扫目录组装名单（唯一真相来源，无登记文件） ---
DISCOVERED="$(mktemp)"; RAWLIST=""; trap 'rm -f "$DISCOVERED" $RAWLIST' EXIT
dup_check="$(ls "$CASES_DIR"/*.sh 2>/dev/null | grep -v '/select-cases\.sh$' || true)"
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
meta_of() { # $1=id -> prints DESC / COST / SUGGEST
  local f="$CASES_DIR/$1.sh" key="$2"
  grep -m1 "^# CASE-$key:" "$f" | sed "s/^# CASE-$key:[[:space:]]*//"
}

# 0) 显式指令优先：skip=一个不跑；full/all=全跑；auto=显式走 Jev 推断；名单=跑指定的
if [ "${E2E_CASES:-}" = "skip" ]; then
  echo "select: explicitly skipped, no cases" >&2
  exit 0
fi
if [ "${E2E_CASES:-}" = "auto" ]; then
  echo "select: explicitly requested Jev inference" >&2
  E2E_CASES=""
fi
if [ -n "${E2E_CASES:-}" ]; then
  KNOWN="$KNOWN" WANT="${E2E_CASES}" python3 - <<'PY'
import os, sys
known = set(os.environ["KNOWN"].split())
want = os.environ["WANT"].strip()
if want in ("all", "full"):
    print(" ".join(["smoke"] + sorted(known - {"smoke"})))
    sys.exit(0)
picked = [w.strip() for w in want.split(",") if w.strip()]
unknown = [w for w in picked if w not in known]
if unknown:
    print(f"FAIL: 未知用例: {','.join(unknown)}；当前可用: {','.join(sorted(known))}", file=sys.stderr)
    sys.exit(1)
print(" ".join(picked))
PY
  exit $?
fi

# 1) 默认走 Jev：base 缺省为上一个 commit（push 由流水线填 before/after 覆盖）

# 1b) 定 base：缺省 HEAD~1；单 commit 仓库取不到时只跑 smoke
if [ -z "${BASE_REF:-}" ]; then
  if git rev-parse -q --verify HEAD~1 >/dev/null 2>&1; then
    BASE_REF="HEAD~1"
  else
    echo "smoke"
    echo "select: single-commit history, smoke only (no model call)" >&2
    exit 0
  fi
fi

# 2) 硬规矩（不经过模型）：Dockerfile.* 动了必带 smoke
FILES="$(git diff --name-only "${BASE_REF}".."${HEAD_REF}" 2>/dev/null || true)"
[ -n "$FILES" ] || { echo "smoke"; echo "select: empty diff, smoke only" >&2; exit 0; }
MUST=""
echo "$FILES" | grep -qE '(^|/)Dockerfile' && MUST="smoke"

# 3) 组装 state：文件清单 + --stat + 完整 diff（体积上限 + 排除锁文件/二进制）
STAT="$(git diff --stat "${BASE_REF}".."${HEAD_REF}" -- . ':(exclude)package-lock.json' ':(exclude)pnpm-lock.yaml' 2>/dev/null | tail -n 30 || true)"
DIFF="$(git diff "${BASE_REF}".."${HEAD_REF}" -- . ':(exclude)package-lock.json' ':(exclude)pnpm-lock.yaml' ':(exclude)*.png' ':(exclude)*.jpg' ':(exclude)*.mp4' 2>/dev/null | head -c "$DIFF_CAP" || true)"

# 4) 调 Jev：每个用例一道 noul 题，并行一次问完
[ -n "${OPENCODE_API_KEY:-}" ] || { echo "FAIL: 缺 OPENCODE_API_KEY（Jev 走 Zen key，手动填 E2E_CASES 可绕过）"; exit 1; }
export FILES STAT DIFF CASES_DIR KNOWN THRESHOLD JEV_URL JEV_MODEL DISCOVERED
RESP="$(mktemp)"; trap 'rm -f "$RESP" "$DISCOVERED"' EXIT
python3 - > "$RESP.req.json" <<'PY'
import json, os, re
known = os.environ["KNOWN"].split()
ids = [c for c in known if c != "smoke"]
def meta(cid, key):
    with open(os.path.join(os.environ["CASES_DIR"], f"{cid}.sh")) as f:
        for line in f:
            m = re.match(rf"^# CASE-{key}:\s*(.*)\s*$", line)
            if m:
                return m.group(1)
    return ""
state = "Changed files:\n" + os.environ.get("FILES", "") + "\n\nDiff stat:\n" + os.environ.get("STAT", "") + "\n\nDiff (truncated):\n" + os.environ.get("DIFF", "")
questions = {}
for cid in ids:
    desc = meta(cid, "DESC"); cost = meta(cid, "COST"); sugg = meta(cid, "SUGGEST")
    questions[f"run_{cid}"] = {
        "type": "noul",
        "instructions": f"Should the '{cid}' E2E case run for these changes? Case: {desc} Cost: {cost}. Hints: {sugg}. Answer yes only if the changes could plausibly affect what this case verifies.",
    }
print(json.dumps({"model": os.environ.get("JEV_MODEL", "jev-1.13-free"), "state": state, "questions": questions}))
PY
HTTP="$(curl -sS -m 90 -o "$RESP" -w '%{http_code}' -H "Authorization: Bearer $OPENCODE_API_KEY" -H 'Content-Type: application/json' --data @"$RESP.req.json" "$JEV_URL" 2>/dev/null || echo "000")"
if [ "$HTTP" != "200" ]; then
  echo "FAIL: Jev 请求失败 HTTP=$HTTP（key/余额/端点见 Troubleshooting；手动填 E2E_CASES 可绕过）" >&2
  head -c 500 "$RESP" >&2 || true; echo >&2
  exit 1
fi

# 5) 解析 + 校验 + 阈值，落盘名单（stdout 一行；明细打 stderr 进 run 日志）
KNOWN_IDS="$KNOWN" python3 - "$RESP" "$THRESHOLD" "$MUST" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
try:
    data = json.loads(raw)
except Exception as e:
    print(f"FAIL: Jev 返回非 JSON: {e}\n{raw[:800]}", file=sys.stderr); sys.exit(1)
answers = data.get("questions") or data.get("answers") or data.get("results") or {}
if not isinstance(answers, dict) or not answers:
    print(f"FAIL: Jev 返回无 questions/answers/results 字段，原样:\n{raw[:1500]}", file=sys.stderr); sys.exit(1)
known = set(("smoke " + __import__("os").environ.get("KNOWN_IDS", "")).split())
unknown_q = [k for k in answers if not (k.startswith("run_") and k[4:] in known)]
if unknown_q:
    print(f"FAIL: Jev 返回未知问题: {','.join(unknown_q)}；原样:\n{raw[:800]}", file=sys.stderr); sys.exit(1)
thr = float(sys.argv[2])
def truthy(v):
    prob = None
    if isinstance(v, dict):
        for k in ("probability", "confidence", "score", "p"):
            if isinstance(v.get(k), (int, float)):
                prob = float(v[k]); break
        for k in ("value", "answer", "decision", "label", "result"):
            if k in v:
                v = v[k]; break
        else:
            v = None
    if isinstance(v, bool):
        return v if prob is None else (v and prob >= thr)
    if isinstance(v, (int, float)):
        return v >= thr
    s = str(v or "").strip().lower()
    if s in ("yes", "true", "y", "1", "run"):
        return True if prob is None else prob >= thr
    if s in ("no", "false", "n", "0", "skip"):
        return False
    return None
picked, audit = [], []
for qid, v in answers.items():
    cid = qid[4:] if qid.startswith("run_") else qid
    if cid not in known or cid == "smoke":
        continue
    t = truthy(v)
    if t is None:
        print(f"FAIL: 问题 {qid} 的答案无法判定 (thr={thr})，原样: {json.dumps(v)[:300]}", file=sys.stderr); sys.exit(1)
    audit.append(f"{cid}={'run' if t else 'skip'} :: {json.dumps(v)[:200]}")
    if t:
        picked.append(cid)
must = (sys.argv[3] or "").split()
out = []
for c in ["smoke"] + sorted(set(picked)):
    if c not in out:
        out.append(c)
for c in must:
    if c not in out:
        out.append(c)
print(" ".join(out))
print("select: " + "; ".join(audit), file=sys.stderr)
PY
