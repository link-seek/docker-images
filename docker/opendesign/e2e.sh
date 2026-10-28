#!/bin/bash
# docker/opendesign/e2e.sh — OD 产品行为门（商家侧；bake-od 构建后自调）。
#
# 断言链（沿用 infra 旧 test-opendesign e2e，迁回商家仓后由 bake-od 在构建后执行）：
#   1) GHCR 同版构建验存活应答（dummy 密钥；容器非 crashloop 即启动链全通）
#   2) 起 litellm 免费档 byok 后端（真 key 调免费模型，不消耗额度）
#   3) 对话三件套：建 project → run → 轮询断言（单聊 / 切模型 / 多轮）
#   4) 免费档别名精确 marker（与生产网关同上游）
#
# 调用约定：env 传 E2E_IMAGE / CANDIDATE_DIGEST / GO_BACKEND_KEY / LITELLM_IMAGE；
# exit 0 + 打印 PASS 行即过。bake-od 只有本脚本绿了才把 temp digest 转正式 tag。
set -uo pipefail

: "${E2E_IMAGE:?E2E_IMAGE required（bake-od 传刚构建的 GHCR ci-<run> tag）}"
: "${GO_BACKEND_KEY:?GO_BACKEND_KEY required（免费档 byok 真 key）}"
LITELLM_IMAGE="${LITELLM_IMAGE:-ghcr.io/link-seek/litellm-gateway:latest}"
OD_NAME="${OD_NAME:-od-e2e}"
LLM_NAME="${LLM_NAME:-litellm-od}"
OD_PORT="${OD_PORT:-7457}"
LLM_PORT="${LLM_PORT:-4001}"
OD="http://127.0.0.1:${OD_PORT}"
AUTH="Authorization: Bearer dummy-token"
WORK="$(mktemp -d)"
: "${WORK:?mktemp -d failed}"
RUN_JSON="$WORK/run.json"
FAIL=""
TSTAT_TEXT=-1
TSTAT_MARK=0

command -v jq >/dev/null || { echo "FAIL: 缺 jq"; exit 1; }
command -v python3 >/dev/null || { echo "FAIL: 缺 python3"; exit 1; }

cleanup() {
  docker rm -f "$OD_NAME" "$LLM_NAME" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

redact() {
  python3 -c '
import os, re, sys
key = os.environ.get("GO_BACKEND_KEY", "")
s = sys.stdin.read()
if key:
    s = s.replace(key, "<redacted>")
s = re.sub(r"sk-[A-Za-z0-9_-]{6}[A-Za-z0-9_-]+", "sk-<redacted>", s)
s = re.sub(r"(Bearer )[A-Za-z0-9._-]+", r"\1<redacted>", s)
sys.stdout.write(s)
'
}

start_od() {
  rm -rf "${WORK:?}/home" "${WORK:?}/od"
  mkdir -p "$WORK/home" "$WORK/od"
  chmod 777 "$WORK/home" "$WORK/od"
  docker rm -f "$OD_NAME" >/dev/null 2>&1 || true
  docker run -d --name "$OD_NAME" --network host \
    -v "$WORK/home:/home/open-design" \
    -v "$WORK/od:/app/.od" \
    -e OD_API_TOKEN=dummy-token \
    -e OD_ALLOWED_ORIGINS=https://example.invalid \
    -e OD_ALLOWED_INTERNAL_HOSTS=127.0.0.1 \
    -e LITELLM_BASE_URL="http://127.0.0.1:${LLM_PORT}" \
    -e LITELLM_API_KEY=dummy \
    -e OD_BIND_HOST=0.0.0.0 -e OD_PORT="$OD_PORT" \
    "$E2E_IMAGE" >/dev/null
}

wait_od() {
  local code i
  for i in $(seq 1 24); do
    code="$(curl -s -m 8 -o /dev/null -w '%{http_code}' "${OD}/" 2>/dev/null || true)"
    code="${code:-000}"
    echo "od-probe#$i -> $code" >&2
    case "$code" in 200|401|403|404) return 0 ;; esac
    sleep 5
  done
  return 1
}

restart_od() {
  docker rm -f "$OD_NAME" >/dev/null 2>&1 || true
  sleep 3
  start_od || return 1
  wait_od || return 1
  echo "od restarted: $(docker inspect "$OD_NAME" --format '{{.Created}} {{.Image}}' | cut -c1-60)"
}

mkproject() {
  local pid="od-ci-${GITHUB_RUN_ID:-$$}-$1" code
  code="$(curl -s -m 15 -o /dev/null -w '%{http_code}' -H "$AUTH" -H 'Content-Type: application/json' \
    -d "{\"id\":\"$pid\",\"name\":\"CI conv $pid\"}" "$OD/api/projects" 2>/dev/null || true)"
  code="${code:-000}"
  echo "mkproject[$1] -> HTTP $code" >&2
  echo "$pid"
}

do_run() {
  local pj="$1" model="$2" msg="$3" cid="${4:-}"
  curl -s -m 15 -H "$AUTH" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg p "$pj" --arg r "req-$(cat /proc/sys/kernel/random/uuid)" \
      --arg m "$msg" --arg mo "$model" --arg k "$GO_BACKEND_KEY" --arg cid "$cid" \
      --arg bu "http://127.0.0.1:${LLM_PORT}/v1" \
      '{projectId:$p, clientRequestId:$r, message:$m, agentId:"byok-opencode", model:$mo,
        byokProvider:{protocol:"openai", apiKey:$k, baseUrl:$bu, model:$mo}}
       | if $cid != "" then . + {conversationId:$cid} else . end')" \
    "$OD/api/runs" || echo '{"error":"CURLFAIL"}'
}

poll_run() {
  local rid="$1" st="?" i
  for i in $(seq 1 45); do
    sleep 10
    curl -s -m 15 -H "$AUTH" "$OD/api/runs/$rid" > "$RUN_JSON" 2>/dev/null || continue
    st="$(python3 -c "import json; print(json.load(open('$RUN_JSON')).get('status','?'))" 2>/dev/null || echo ?)"
    echo "poll#$i -> $st" >&2
    case "$st" in succeeded|failed|canceled) break ;; esac
  done
  echo "$st"
}

tstat() {
  local out
  out="$(docker exec "$OD_NAME" sh -c "cat /app/.od/runs/$1/events.jsonl 2>/dev/null" | python3 -c "
import json,sys
tl=0; mk=0; want=sys.argv[1]
for line in sys.stdin:
    try: o=json.loads(line)
    except: continue
    st=[o]
    while st:
        x=st.pop()
        if isinstance(x,dict): st.extend(x.values())
        elif isinstance(x,list): st.extend(x)
        elif isinstance(x,str):
            t=x.strip()
            if len(t)>20: tl+=len(t)
            if want and want in t: mk=1
print(f'textlen={tl} marker={mk}')" "$2" 2>/dev/null || echo "textlen=-1 marker=0")"
  TSTAT_TEXT="$(echo "$out" | grep -oP 'textlen=\K-?\d+' || echo -1)"
  TSTAT_MARK="$(echo "$out" | grep -oP 'marker=\K[01]' || echo 0)"
  echo "transcript: textlen=$TSTAT_TEXT marker=$TSTAT_MARK"
}

dump_run() {
  echo "===== $1 run JSON（截断脱敏） ====="
  python3 -c "import json; d=json.load(open('$RUN_JSON')); print(json.dumps({k:d.get(k) for k in ('id','status','error','errorCode','conversationId','assistantMessageId','deliverableValid','deliverableEntryFile','model','agentId')}, ensure_ascii=False)[:800])" 2>/dev/null || echo "(parse fail)"
  local rid
  rid="$(python3 -c "import json; print(json.load(open('$RUN_JSON')).get('id',''))" 2>/dev/null || true)"
  if [ -n "$rid" ]; then
    echo "===== $1 agent 事件头（脱敏，看发给 CLI 的精确模型串） ====="
    docker exec "$OD_NAME" sh -c "head -c 2000 /app/.od/runs/$rid/events.jsonl 2>/dev/null || echo '(无 events 文件)'" | redact | head -c 2000; echo
    echo "===== $1 agent 事件尾（脱敏） ====="
    docker exec "$OD_NAME" sh -c "tail -c 2000 /app/.od/runs/$rid/events.jsonl 2>/dev/null || echo '(无 events 文件)'" | redact | head -c 2000; echo
    echo "===== $1 transcript 统计（解码后） ====="
    docker exec "$OD_NAME" sh -c "cat /app/.od/runs/$rid/events.jsonl 2>/dev/null" | python3 -c "
import json,sys,re
tl=0; hits={}
for line in sys.stdin:
    try: o=json.loads(line)
    except: continue
    st=[o]
    while st:
        x=st.pop()
        if isinstance(x,dict): st.extend(x.values())
        elif isinstance(x,list): st.extend(x)
        elif isinstance(x,str):
            t=x.strip()
            if len(t)>20: tl+=len(t)
            for m in re.findall(r'OD-[A-Z-]+|7421', t): hits[m]=hits.get(m,0)+1
print(f'textlen={tl} markers={hits}')" 2>/dev/null || echo "(transcript 统计失败)"
  fi
}

echo "===== 1/3 GHCR 同版构建存活（$E2E_IMAGE） ====="
docker pull -q "$E2E_IMAGE" || { echo "FAIL: 拉取 $E2E_IMAGE 失败"; exit 1; }
if [ -n "${CANDIDATE_DIGEST:-}" ]; then
  GOT="$(docker image inspect "$E2E_IMAGE" --format '{{index .RepoDigests 0}}' 2>/dev/null | sed 's/.*@//')"
  [ "$GOT" = "$CANDIDATE_DIGEST" ] || { echo "FAIL: 被测镜像 digest=$GOT，不是刚构建的 $CANDIDATE_DIGEST"; exit 1; }
  echo "IDENTITY OK: $E2E_IMAGE == $CANDIDATE_DIGEST"
fi
start_od || { echo "FAIL: OD 启动失败"; exit 1; }
if ! wait_od; then
  docker logs "$OD_NAME" --tail 40 2>&1 | redact || true
  echo "FAIL: 2 分钟无 HTTP 应答或已死"
  exit 1
fi
echo "===== / 响应体采样（脱敏，供行为对账） ====="
curl -s -m 8 "${OD}/" | redact | head -c 400; echo
docker logs "$OD_NAME" --tail 8 2>&1 | redact || true
docker ps --filter "name=${OD_NAME}" --format '{{.Status}}' | grep -q "Up" || { echo "FAIL: 容器已死"; exit 1; }
echo "BOOT OK: GHCR 同版构建应答且存活"

echo "===== 2/3 起 byok 后端（litellm 免费档，$LITELLM_IMAGE） ====="
cat > "$WORK/litellm.yaml" <<'YAML'
# 注意：drop_params 必须放 litellm_settings（general_settings 下那份 responses 路径不认，
# OD 驱动的新版 opencode CLI 会发 store 参数，后端直接拒）。
# forward_client_headers 必开：免费档锁 OpenCode 客户端，头不到上游就 403。
# custom_auth/passthrough 必开：否则 litellm 把 byok key 当虚拟 key 查 DB，直接 No connected db。
general_settings:
  drop_params: true
  forward_client_headers_to_llm_api: true
  dangerously_permit_weak_or_unset_master_key: true
  custom_auth: always_allow_auth.always_allow
litellm_settings:
  drop_params: true
  request_timeout: 120
  num_retries: 2
  callbacks: passthrough_key.passthrough_callback
model_list:
  - model_name: test-chat
    litellm_params: &free
      # Go 免费档：beam-free 走 Go 端点（需客户端 x-opencode-session，OD/opencode 自带，
      # forward_client_headers 透传）；旧 Zen 免费端点按 IP 限流，CI 上不可靠。
      model: openai/beam-free
      api_base: https://opencode.ai/inference/go/openai/v1
      api_key: os.environ/GO_BACKEND_KEY
      timeout: 120
  - model_name: test-chat-b
    litellm_params: *free
  # OD 会给部分 byok 模型加 open-design-byok/ 前缀，网关侧同上游双注册
  - model_name: open-design-byok/test-chat
    litellm_params: *free
  - model_name: open-design-byok/test-chat-b
    litellm_params: *free
  - model_name: free-probe-a
    litellm_params: *free
  - model_name: open-design-byok/free-probe-a
    litellm_params: *free
YAML
docker pull -q "$LITELLM_IMAGE" || { echo "FAIL: 拉取后端镜像 $LITELLM_IMAGE 失败"; exit 1; }
docker rm -f "$LLM_NAME" >/dev/null 2>&1 || true
docker run -d --name "$LLM_NAME" --network host \
  -v "$WORK/litellm.yaml:/app/config.yaml:ro" \
  -e GO_BACKEND_KEY="$GO_BACKEND_KEY" \
  -e LITELLM_MASTER_KEY=test-only \
  -e DISABLE_ADMIN_UI=True \
  "$LITELLM_IMAGE" --config /app/config.yaml --port "$LLM_PORT" >/dev/null
READY=0
for i in $(seq 1 36); do
  if curl -sf --max-time 5 "http://127.0.0.1:${LLM_PORT}/v1/models" -H "Authorization: Bearer test-only" >/dev/null 2>&1; then
    READY=1; break
  fi
  sleep 5
done
if [ "$READY" != 1 ]; then
  docker logs "$LLM_NAME" --tail 60 2>&1 | redact || true
  echo "FAIL: byok 后端 3 分钟未就绪"
  exit 1
fi
echo "BACKEND OK: litellm 免费档就绪（:${LLM_PORT}）"

echo "===== 3/3 OD 对话三件套（建 project → run → 轮询断言） ====="
# 每个模型独立 project（独立默认 conversation；OD 疑似按 conversation 缓存 provider 配置，
# 同会话换模型会被拒 no-route；多轮显式复用 turn1 的 conversationId 延续上下文）。
# 切模型/多轮/免费档各自重启全新 daemon＋数据目录（provider 目录缓存在磁盘 /app/.od，首模型写死）。

# Phase A 单聊（boot daemon，test-chat；门=成功＋实质文本，marker 仅记录）
PID="$(mkproject base)"
echo "project: $PID"
R1="$(do_run "$PID" test-chat "reply with exactly: OD-CONV-OK")"
RID1="$(echo "$R1" | python3 -c "import json,sys; print(json.load(sys.stdin).get('runId',''))" 2>/dev/null || true)"
echo "run1: ${RID1:0:12}..."
if [ -z "$RID1" ]; then
  echo "FAIL: run1 未返回 runId"
  FAIL="$FAIL; 单聊未受理"
else
  ST1="$(poll_run "$RID1")"
  tstat "$RID1" "OD-CONV-OK"
  echo "### OD 单聊: status=$ST1 textlen=$TSTAT_TEXT marker=$TSTAT_MARK"
  if [ "$ST1" = "succeeded" ] && [ "${TSTAT_TEXT:--1}" -ge 200 ]; then
    echo "OK: OD 单聊（test-chat，事件流有实质文本）"
  else
    echo "FAIL: 单聊 status=$ST1"; dump_run 单聊; FAIL="$FAIL; OD 单聊失败($ST1)"
  fi
fi

# Phase B 切模型（全新 daemon＋新 project；provider 疑似按 daemon 缓存首个模型）
if restart_od; then
  PID2="$(mkproject switch)"
  echo "project2: $PID2"
  R2="$(do_run "$PID2" test-chat-b "reply with exactly: OD-SWITCH-OK")"
  RID2="$(echo "$R2" | python3 -c "import json,sys; print(json.load(sys.stdin).get('runId',''))" 2>/dev/null || true)"
  echo "run2: ${RID2:0:12}..."
  if [ -z "$RID2" ]; then
    echo "FAIL: run2 未返回 runId"
    FAIL="$FAIL; 切模型未受理"
  else
    ST2="$(poll_run "$RID2")"
    tstat "$RID2" "OD-SWITCH-OK"
    echo "### OD 切模型: status=$ST2 textlen=$TSTAT_TEXT marker=$TSTAT_MARK"
    if [ "$ST2" = "succeeded" ] && [ "${TSTAT_TEXT:--1}" -ge 200 ]; then
      echo "OK: OD 切模型（test-chat-b，新 daemon，实质文本回环）"
    else
      echo "FAIL: 切模型 status=$ST2"; dump_run 切模型; FAIL="$FAIL; OD 切模型失败($ST2)"
    fi
  fi
else
  echo "FAIL: 切模型前重启 OD 未就绪"
  FAIL="$FAIL; 切模型重启失败"
fi

# Phase D 多轮（全新 daemon＋新 project；turn2 显式复用 turn1 的 conversationId，必须原样召回 7421）
if restart_od; then
  PIDM="$(mkproject multi)"
  echo "project-multi: $PIDM"
  R3="$(do_run "$PIDM" test-chat "记住这个数字：7421，收到只回复：记住了")"
  RID3="$(echo "$R3" | python3 -c "import json,sys; print(json.load(sys.stdin).get('runId',''))" 2>/dev/null || true)"
  CID3="$(echo "$R3" | python3 -c "import json,sys; print(json.load(sys.stdin).get('conversationId',''))" 2>/dev/null || true)"
  echo "conversation: $CID3"
  ST3="skip"
  if [ -n "$RID3" ]; then
    ST3="$(poll_run "$RID3")"
    if [ "$ST3" != "succeeded" ]; then
      echo "FAIL: 多轮 turn1 status=$ST3"; dump_run 多轮turn1; FAIL="$FAIL; OD 多轮turn1失败($ST3)"
    fi
  else
    FAIL="$FAIL; OD 多轮turn1未受理"
  fi
  echo "turn1: $ST3"
  R4="$(do_run "$PIDM" test-chat "我让你记的数字是多少？只回复数字" "$CID3")"
  RID4="$(echo "$R4" | python3 -c "import json,sys; print(json.load(sys.stdin).get('runId',''))" 2>/dev/null || true)"
  ST4="skip"
  TSTAT_TEXT=-1; TSTAT_MARK=0
  if [ -n "$RID4" ]; then
    ST4="$(poll_run "$RID4")"
    tstat "$RID4" "7421"
    echo "### OD 多轮 turn2: status=$ST4 textlen=$TSTAT_TEXT marker=$TSTAT_MARK"
  fi
  if [ "$ST4" = "succeeded" ] && [ "$TSTAT_MARK" = "1" ]; then
    echo "OK: OD 多轮（同 conversation，7421 召回）"
  else
    echo "FAIL: 多轮 turn2 status=$ST4"; dump_run 多轮; FAIL="$FAIL; OD 多轮失败($ST4)"
  fi
else
  echo "FAIL: 多轮前重启 OD 未就绪"
  FAIL="$FAIL; 多轮重启失败"
fi

# Phase C 免费档（全新 daemon＋新 project；beam-free 要求 marker 精确命中）
if restart_od; then
  PIDF="$(mkproject free)"
  echo "project-free: $PIDF"
  RF="$(do_run "$PIDF" free-probe-a "reply with exactly: OD-FREE-OK" \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('runId',''))" 2>/dev/null || true)"
  echo "run-free: ${RF:0:12}..."
  STF="skip"
  TSTAT_TEXT=-1; TSTAT_MARK=0
  if [ -n "$RF" ]; then
    STF="$(poll_run "$RF")"
    tstat "$RF" "OD-FREE-OK"
    echo "### OD 免费档: status=$STF textlen=$TSTAT_TEXT marker=$TSTAT_MARK"
  fi
  if [ "$STF" = "succeeded" ] && [ "$TSTAT_MARK" = "1" ]; then
    echo "OK: OD 免费档（free-probe-a 真 key，marker 精确命中）"
  else
    echo "FAIL: 免费档 status=$STF"; dump_run 免费档; FAIL="$FAIL; OD 免费档失败($STF)"
  fi
else
  echo "FAIL: 免费档前重启 OD 未就绪"
  FAIL="$FAIL; 免费档重启失败"
fi

if [ -n "$FAIL" ]; then
  echo "FAIL: OD 产品 e2e 未过:${FAIL}"
  exit 1
fi
echo "PASS: OD 产品 e2e 全绿（GHCR 存活 + 单聊/切模型/多轮 + 免费档）"
