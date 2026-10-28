#!/bin/bash
# bake-od 产品 e2e：被测 OD 镜像（GHCR 同版构建）＋ litellm 免费档后端，跑对话三件套。
# 调用约定（bake-od.yml 固定）：env 传 IMAGE_REF / GATEWAY_IMAGE / GO_BACKEND_KEY；exit 0 即过。
# 三件套：单聊、切模型（新 daemon 隔离 provider 首模型缓存）、多轮（同 project 默认会话召回 7421）。
set -uo pipefail

: "${IMAGE_REF:?IMAGE_REF required（被测镜像，如 ghcr.io/link-seek/opendesign:ci-<run>）}"
: "${GATEWAY_IMAGE:?GATEWAY_IMAGE required（litellm 网关镜像）}"
: "${GO_BACKEND_KEY:?GO_BACKEND_KEY required（免费档 byok key）}"

OD_PORT="${OD_PORT:-7457}"
BACKEND_PORT="${BACKEND_PORT:-4001}"
OD_TOKEN="${OD_TOKEN:-dummy-token}"
OD="http://127.0.0.1:${OD_PORT}"
AUTH="Authorization: Bearer ${OD_TOKEN}"
RUN_PREFIX="od-ci-${GITHUB_RUN_ID:-local}-$(date -u +%s)"
WORK="$(mktemp -d /tmp/od-e2e.XXXXXX)"
HOME_DIR="$WORK/home"
OD_DIR="$WORK/od"
BACKEND_CFG="$WORK/litellm-od.yaml"
TSTAT_TEXT=-1
TSTAT_MARK=0
FAIL=""

cleanup() {
  docker rm -f od-e2e litellm-od >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

render_backend() {
  # drop_params 必须放 litellm_settings（general_settings 下 responses 路径不认）；
  # forward_client_headers 必开：免费档锁 OpenCode 客户端，头不到上游就 403。
  cat > "$BACKEND_CFG" <<'YAML'
general_settings:
  drop_params: true
  forward_client_headers_to_llm_api: true
litellm_settings:
  drop_params: true
  request_timeout: 120
  num_retries: 2
model_list:
  - model_name: test-chat
    litellm_params:
      model: openai/deepseek-v4.1-flash-free
      api_base: https://opencode.ai/inference/openai/v1
      api_key: os.environ/GO_BACKEND_KEY
      timeout: 120
  - model_name: test-chat-b
    litellm_params:
      model: openai/deepseek-v4.1-flash-free
      api_base: https://opencode.ai/inference/openai/v1
      api_key: os.environ/GO_BACKEND_KEY
      timeout: 120
  - model_name: open-design-byok/test-chat
    litellm_params:
      model: openai/deepseek-v4.1-flash-free
      api_base: https://opencode.ai/inference/openai/v1
      api_key: os.environ/GO_BACKEND_KEY
      timeout: 120
  - model_name: open-design-byok/test-chat-b
    litellm_params:
      model: openai/deepseek-v4.1-flash-free
      api_base: https://opencode.ai/inference/openai/v1
      api_key: os.environ/GO_BACKEND_KEY
      timeout: 120
YAML
}

start_od() {
  docker rm -f od-e2e >/dev/null 2>&1 || true
  rm -rf "$HOME_DIR" "$OD_DIR"
  mkdir -p "$HOME_DIR" "$OD_DIR"
  chmod 777 "$HOME_DIR" "$OD_DIR"
  docker run -d --name od-e2e --network host \
    -v "$HOME_DIR:/home/open-design" \
    -v "$OD_DIR:/app/.od" \
    -e OD_API_TOKEN="$OD_TOKEN" \
    -e OD_ALLOWED_ORIGINS=https://example.invalid \
    -e OD_ALLOWED_INTERNAL_HOSTS=127.0.0.1 \
    -e LITELLM_BASE_URL="http://127.0.0.1:${BACKEND_PORT}" \
    -e LITELLM_API_KEY=dummy \
    -e OD_BIND_HOST=0.0.0.0 \
    -e OD_PORT="$OD_PORT" \
    "$IMAGE_REF" >/dev/null
  local code="" pass=""
  for i in $(seq 1 36); do
    code="$(curl -s -m 8 -o /dev/null -w '%{http_code}' "$OD/" || echo 000)"
    echo "boot-probe#$i -> $code"
    case "$code" in 200|401|403|404) pass=1; break;; esac
    sleep 5
  done
  echo "===== / 响应体采样（脱敏，供行为对账） ====="
  curl -s -m 8 "$OD/" | sed -E -e 's/(sk-[A-Za-z0-9_-]{6})[A-Za-z0-9_-]+/\1<redacted>/g' | head -c 400; echo
  docker logs od-e2e --tail 8 || true
  [ -n "$pass" ] || { echo "FAIL: 3 分钟无 HTTP 应答"; return 1; }
  docker ps --filter name=od-e2e --format '{{.Status}}' | grep -q "Up" || { echo "FAIL: 容器已死"; return 1; }
  echo "OK: 镜像存活应答（$IMAGE_REF）"
}

start_backend() {
  render_backend
  docker rm -f litellm-od >/dev/null 2>&1 || true
  docker run -d --name litellm-od --network host \
    -v "$BACKEND_CFG:/app/config.yaml:ro" \
    -e GO_BACKEND_KEY="$GO_BACKEND_KEY" \
    -e LITELLM_MASTER_KEY=test-only \
    -e DISABLE_ADMIN_UI=True \
    "$GATEWAY_IMAGE" --config /app/config.yaml --port "$BACKEND_PORT" >/dev/null
  local ok=""
  for i in $(seq 1 24); do
    if curl -sf --max-time 5 "http://127.0.0.1:${BACKEND_PORT}/v1/models" \
      -H "Authorization: Bearer test-only" >/dev/null 2>&1; then
      ok=1
      break
    fi
    sleep 5
  done
  [ -n "$ok" ] || { echo "FAIL: backend 2 分钟未就绪"; docker logs litellm-od --tail 30 || true; return 1; }
  echo "OK: backend 就绪（litellm:${BACKEND_PORT} 免费档）"
}

mkproject() {
  local pid="$RUN_PREFIX-$1" code
  code="$(curl -s -m 15 -o /dev/null -w '%{http_code}' -H "$AUTH" -H 'Content-Type: application/json' \
    -d "{\"id\":\"$pid\",\"name\":\"CI conv $pid\"}" "$OD/api/projects" || echo 000)"
  echo "$code" >&2
  echo "$pid"
}

do_run() {
  local pj="$1" model="$2" msg="$3" rid
  rid="req-$(cat /proc/sys/kernel/random/uuid)"
  curl -s -m 15 -H "$AUTH" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg p "$pj" --arg r "$rid" --arg m "$msg" --arg mo "$model" \
      --arg k "$GO_BACKEND_KEY" --arg b "http://127.0.0.1:${BACKEND_PORT}/v1" \
      '{projectId:$p, clientRequestId:$r, message:$m, agentId:"byok-opencode", model:$mo,
        byokProvider:{protocol:"openai", apiKey:$k, baseUrl:$b, model:$mo}}')" \
    "$OD/api/runs" || echo '{"error":"CURLFAIL"}'
}

poll_run() {
  local rid="$1" st="?"
  for i in $(seq 1 30); do
    sleep 10
    curl -s -m 15 -H "$AUTH" "$OD/api/runs/$rid" > "$WORK/odrun.json" 2>/dev/null || continue
    st="$(python3 -c "import json; print(json.load(open('$WORK/odrun.json')).get('status','?'))" 2>/dev/null || echo ?)"
    echo "poll#$i -> $st" >&2
    case "$st" in succeeded|failed|canceled) break;; esac
  done
  echo "$st"
}

tstat() {
  local rid="$1" marker="$2" out
  out="$(docker exec od-e2e sh -c "cat /app/.od/runs/$rid/events.jsonl 2>/dev/null" | python3 -c '
import json, sys
want = sys.argv[1]
tl = 0
mk = 0
for line in sys.stdin:
    try: o = json.loads(line)
    except Exception: continue
    st = [o]
    while st:
        x = st.pop()
        if isinstance(x, dict): st.extend(x.values())
        elif isinstance(x, list): st.extend(x)
        elif isinstance(x, str):
            t = x.strip()
            if len(t) > 20: tl += len(t)
            if want and want in t: mk = 1
print(f"textlen={tl} marker={mk}")
' "$marker" 2>/dev/null || echo "textlen=-1 marker=0")"
  TSTAT_TEXT="$(echo "$out" | grep -oP 'textlen=\K-?\d+' || echo -1)"
  TSTAT_MARK="$(echo "$out" | grep -oP 'marker=\K[01]' || echo 0)"
  echo "transcript: textlen=$TSTAT_TEXT marker=$TSTAT_MARK"
}

redact() {
  sed -E -e 's/(sk-[A-Za-z0-9_-]{6})[A-Za-z0-9_-]+/\1<redacted>/g' \
    -e 's/(Bearer )[A-Za-z0-9_.-]+/\1<redacted>/g'
}

dump_run() {
  local label="$1" rid
  echo "===== $label run JSON（截断脱敏） ====="
  python3 -c "import json; d=json.load(open('$WORK/odrun.json')); print(json.dumps({k:d.get(k) for k in ('id','status','error','errorCode','conversationId','assistantMessageId','deliverableValid','deliverableEntryFile','model','agentId')}, ensure_ascii=False)[:800])" 2>/dev/null || echo "(parse fail)"
  rid="$(python3 -c "import json; print(json.load(open('$WORK/odrun.json')).get('id',''))" 2>/dev/null || true)"
  [ -n "$rid" ] || return 0
  echo "===== $label agent 事件头（脱敏） ====="
  docker exec od-e2e sh -c "head -c 2000 /app/.od/runs/$rid/events.jsonl 2>/dev/null || echo '(无 events 文件)'" | redact | head -c 2000; echo
  echo "===== $label agent 事件尾（脱敏） ====="
  docker exec od-e2e sh -c "tail -c 2000 /app/.od/runs/$rid/events.jsonl 2>/dev/null || echo '(无 events 文件)'" | redact | head -c 2000; echo
}

run_rid() {
  python3 -c "import json,sys; print(json.load(sys.stdin).get('runId',''))" 2>/dev/null || true
}

start_od || { echo "FAIL: OD 启动失败"; exit 1; }
start_backend || { echo "FAIL: backend 启动失败"; exit 1; }

# Phase A 单聊（boot daemon，test-chat；门=成功＋实质文本）
PID="$(mkproject base)"
echo "project: $PID"
R1="$(do_run "$PID" test-chat "reply with exactly: OD-CONV-OK")"
RID1="$(printf '%s' "$R1" | run_rid)"
echo "run1: ${RID1:0:12}..."
if [ -n "$RID1" ]; then
  ST1="$(poll_run "$RID1")"
  tstat "$RID1" "OD-CONV-OK"
  echo "### OD 单聊: status=$ST1 textlen=$TSTAT_TEXT marker=$TSTAT_MARK"
  if [ "$ST1" = "succeeded" ] && [ "${TSTAT_TEXT:--1}" -ge 200 ]; then
    echo "OK: OD 单聊（test-chat，事件流有实质文本）"
  else
    echo "FAIL: 单聊 status=$ST1"; dump_run 单聊; FAIL="$FAIL; OD 单聊失败($ST1)"
  fi
else
  echo "FAIL: run1 未返回 runId"; echo "raw: $(printf '%s' "$R1" | head -c 400)"
  FAIL="$FAIL; 单聊未受理"
fi

# Phase B 切模型（全新 daemon＋新 project；provider 疑似按 daemon 缓存首个模型）
start_od || { echo "FAIL: 切模型前重启 OD 失败"; exit 1; }
PID2="$(mkproject switch)"
echo "project2: $PID2"
R2="$(do_run "$PID2" test-chat-b "reply with exactly: OD-SWITCH-OK")"
RID2="$(printf '%s' "$R2" | run_rid)"
echo "run2: ${RID2:0:12}..."
if [ -n "$RID2" ]; then
  ST2="$(poll_run "$RID2")"
  tstat "$RID2" "OD-SWITCH-OK"
  echo "### OD 切模型: status=$ST2 textlen=$TSTAT_TEXT marker=$TSTAT_MARK"
  if [ "$ST2" = "succeeded" ] && [ "${TSTAT_TEXT:--1}" -ge 200 ]; then
    echo "OK: OD 切模型（test-chat-b，新 daemon，实质文本回环）"
  else
    echo "FAIL: 切模型 status=$ST2"; dump_run 切模型; FAIL="$FAIL; OD 切模型失败($ST2)"
  fi
else
  echo "FAIL: run2 未返回 runId"; echo "raw: $(printf '%s' "$R2" | head -c 400)"
  FAIL="$FAIL; 切模型未受理"
fi

# Phase D 多轮（全新 daemon＋新 project；turn2 必须原样召回 7421）
start_od || { echo "FAIL: 多轮前重启 OD 失败"; exit 1; }
PIDM="$(mkproject multi)"
echo "project-multi: $PIDM"
R3="$(do_run "$PIDM" test-chat "记住这个数字：7421，收到只回复：记住了")"
RID3="$(printf '%s' "$R3" | run_rid)"
ST3="skip"; [ -n "$RID3" ] && ST3="$(poll_run "$RID3")"
echo "turn1: $ST3"
R4="$(do_run "$PIDM" test-chat "我让你记的数字是多少？只回复数字")"
RID4="$(printf '%s' "$R4" | run_rid)"
ST4="skip"; [ -n "$RID4" ] && ST4="$(poll_run "$RID4")"
if [ -n "$RID4" ]; then
  tstat "$RID4" "7421"
  echo "### OD 多轮 turn2: status=$ST4 textlen=$TSTAT_TEXT marker=$TSTAT_MARK"
fi
if [ "$ST4" = "succeeded" ] && [ "$TSTAT_MARK" = "1" ]; then
  echo "OK: OD 多轮（同 project 默认会话，7421 召回）"
else
  echo "FAIL: 多轮 turn2 status=$ST4"; dump_run 多轮; FAIL="$FAIL; OD 多轮失败($ST4)"
fi

if [ -n "$FAIL" ]; then
  echo "FAIL: OD 产品 e2e 未过:$FAIL"
  exit 1
fi
echo "E2E OK: OD 对话三件套通过（单聊/切模型/多轮）"
