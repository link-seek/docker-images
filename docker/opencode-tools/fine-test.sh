#!/bin/bash
# docker/opencode-tools/fine-test.sh — tools 产品细测（商家实现，骨架按固定约定调用）。
# 调用约定（bake-stack.yml 写死）：env 传 DIGEST / API_KEY / SWR_USER / SWR_PASS / TEMP_TAG / E2E_CASES
# + K8S_NS / K8S_DEPLOY / K8S_CONTAINER（k3d+Flux 新预检，#505）；exit 0 + 打印 PASS 行即过，非零即红。
#
# 新预检：同货验证。骨架已在 k3d 里用 Flux 对完账（digest 经 images 注入），本 hook 只做：
#   1) identity：跑的必须是刚打出来的 digest（kubectl 读 deploy image）。
#   2) E2E：select-cases.sh 选单（默认 full；E2E_CASES 可 skip/名单强制），逐个跑 e2e-cases/case-*.sh。
#      用例全部 kubectl exec 打 $K8S_DEPLOY；smoke 为内置，不需要文件。
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASES_DIR="$HOOK_DIR/e2e-cases"

[ -n "${K8S_DEPLOY:-}" ] || { echo "FAIL: K8S_DEPLOY 为空（骨架 k8s_app 未传）"; exit 1; }
[ -n "${DIGEST:-}" ] || { echo "FAIL: DIGEST 为空（temp 推送未出 digest）"; exit 1; }
K8S_NS="${K8S_NS:-opencode}"
K8S_CONTAINER="${K8S_CONTAINER:-$K8S_DEPLOY}"
export K8S_NS K8S_DEPLOY K8S_CONTAINER
export K8S_EXEC="kubectl exec -n $K8S_NS deploy/$K8S_DEPLOY -c $K8S_CONTAINER --"

identity() { # 货对单：跑的必须是刚打出来的 digest
  local img
  img="$(kubectl -n "$K8S_NS" get "deploy/$K8S_DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].image}')"
  [ -n "$img" ] || { echo "FAIL: deploy/$K8S_DEPLOY 读不到 image"; exit 1; }
  case "$img" in
    *"@${DIGEST}") echo "IDENTITY OK: deploy/$K8S_DEPLOY == $DIGEST" ;;
    *) echo "FAIL: deploy 跑的是 $img，不是刚打出来的 $DIGEST"; exit 1 ;;
  esac
}

identity

# --- E2E 选单 + 逐个跑 ---
CASES="$(E2E_CASES="${E2E_CASES:-}" bash "$CASES_DIR/select-cases.sh")"
echo "E2E cases: ${CASES:-<none>}"

# --- 宿主真连靶：case-ssh 要验“容器 → 宿主”这条真实形态（生产直连 .21 同构）。
# 宿主 sshd 现起在本 runner（ephemeral，即焚），地址+临时 key 递进 pod；验完即拆。
case_selected() { case " ${CASES:-} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
HOST_BAIT_DIR=/tmp/e2e-host-ssh
host_bait_pid=""

host_bait_bridge_ip() { # pod 出网经 k3d node 容器，宿主 = node 的默认网关
  local node ip
  node="$(docker ps --filter "name=k3d-preflight-server-0" --format '{{.ID}}' 2>/dev/null | head -1 || true)"
  if [ -n "$node" ]; then
    ip="$(docker exec "$node" sh -c "ip route | awk '/^default/{print \$3}'" 2>/dev/null || true)"
  fi
  if [ -z "${ip:-}" ]; then
    ip="$(ip -4 -o addr show docker0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1 || true)"
  fi
  printf '%s' "${ip:-}"
}

host_bait_up() {
  local ip
  if ! command -v sshd >/dev/null 2>&1; then
    echo "CASE-INFO: runner 无 sshd，ephemeral 现装 openssh-server（不进镜像）"
    sudo apt-get update -qq >/dev/null 2>&1 || true
    sudo apt-get install -y -qq openssh-server >/dev/null 2>&1 \
      || { echo "CASE-INFO: 宿主 sshd 装不上，case-ssh 回落容器内 loopback"; return 1; }
  fi
  ip="$(host_bait_bridge_ip)"
  [ -n "$ip" ] || { echo "CASE-INFO: 取不到宿主网桥 IP，case-ssh 回落 loopback"; return 1; }
  rm -rf "$HOST_BAIT_DIR"; mkdir -p "$HOST_BAIT_DIR"
  ssh-keygen -t ed25519 -N '' -f "$HOST_BAIT_DIR/host_ed25519" -q || return 1
  ssh-keygen -t ed25519 -N '' -f "$HOST_BAIT_DIR/client_ed25519" -q || return 1
  cp "$HOST_BAIT_DIR/client_ed25519.pub" "$HOST_BAIT_DIR/authorized_keys"
  chmod 600 "$HOST_BAIT_DIR/authorized_keys" "$HOST_BAIT_DIR/client_ed25519" "$HOST_BAIT_DIR/host_ed25519"
  sudo mkdir -p /run/sshd
  # 用独立 sshd_config 而不是一串 -o：选项多时更可读，且 -E 日志便于失败定位。
  cat > "$HOST_BAIT_DIR/sshd_config" <<EOF
Port 2222
ListenAddress 0.0.0.0
HostKey $HOST_BAIT_DIR/host_ed25519
PidFile $HOST_BAIT_DIR/sshd.pid
AuthorizedKeysFile $HOST_BAIT_DIR/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
StrictModes no
# runner 账号无密码（锁定哈希）：UsePAM no 时 sshd 会以 account locked 拒登，走系统默认 UsePAM
UsePAM yes
PasswordAuthentication no
LogLevel VERBOSE
EOF
  sudo /usr/sbin/sshd -f "$HOST_BAIT_DIR/sshd_config" -E "$HOST_BAIT_DIR/sshd.log" \
    || { echo "CASE-INFO: 宿主 sshd 起不来，回落 loopback"; sudo cat "$HOST_BAIT_DIR/sshd.log" 2>/dev/null | tail -5; return 1; }
  chmod 644 "$HOST_BAIT_DIR/sshd.log" 2>/dev/null || true
  host_bait_pid="$HOST_BAIT_DIR/sshd.pid"
  TSSH_HOST_BAIT="$(whoami)@${ip}:2222"
  export TSSH_HOST_BAIT TSSH_HOST_BAIT_KEY="$HOST_BAIT_DIR/client_ed25519"
  echo "CASE-INFO: 宿主真连靶就绪 $TSSH_HOST_BAIT（pod → runner 网桥）"
}

host_bait_down() {
  [ -n "${host_bait_pid:-}" ] && [ -f "$host_bait_pid" ] && sudo kill "$(cat "$host_bait_pid")" 2>/dev/null || true
  rm -rf "$HOST_BAIT_DIR"
}

if case_selected case-ssh; then
  trap host_bait_down EXIT
  host_bait_up || true
fi

smoke() { # 内置兜底：版本 + skill 文件存在（快、无网、无模型）
  $K8S_EXEC opencode --version
  $K8S_EXEC test -f /root/.agents/skills/open-design/SKILL.md
  echo "E2E PASS: smoke"
}

if [ -z "$CASES" ]; then
  echo "E2E SKIP: 选单为空（E2E_CASES=skip）"
else
  for c in $CASES; do
    if [ "$c" = "smoke" ]; then
      smoke
    else
      [ -f "$CASES_DIR/$c.sh" ] || { echo "FAIL: 用例文件缺失 $CASES_DIR/$c.sh（选单与文件不一致）"; exit 1; }
      bash "$CASES_DIR/$c.sh"
      echo "E2E PASS: $c"
    fi
  done
fi

echo "FINE PASS: tools 细测通过（k3d+Flux 同货，E2E cases: ${CASES:-<none>}）"
