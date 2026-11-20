#!/bin/bash
# CASE-ID: case-ssh
# CASE-DESC: tssh 直连包装可用（help/缺 key 报错/dry-run 固定选项/容器→宿主真连，无模型）
# CASE-COST: medium
# CASE-SUGGEST: tssh.sh/Dockerfile/goss 链动了就跑；真连打 fine-test.sh 现起的宿主 sshd（runner 网桥，test-only），不碰生产主机；本地单跑回落容器内 loopback。
set -euo pipefail
[ -n "${K8S_EXEC:-}" ] || { echo "FAIL: K8S_EXEC 为空（fine-test.sh 未导出）"; exit 1; }

# 1) help 可用
timeout 30 $K8S_EXEC tssh --help > /tmp/case-ssh-help.out 2>&1 \
  || { echo "FAIL: tssh --help 失败"; cat /tmp/case-ssh-help.out 2>/dev/null || true; exit 1; }
grep -q 'tssh' /tmp/case-ssh-help.out \
  || { echo "FAIL: tssh --help 输出异常"; exit 1; }

# 2) 无 key 直接报错（exit 2，不回落密码；不真连）
if timeout 30 $K8S_EXEC env TSSH_KEY=/tmp/definitely-missing-tssh-key tssh dummyhost -- echo hi > /tmp/case-ssh-nokey.out 2>&1; then
  echo "FAIL: 缺 key 时 tssh 应失败却成功了（回落密码？）"
  exit 1
fi
grep -q '缺少私钥' /tmp/case-ssh-nokey.out \
  || { echo "FAIL: 缺 key 报错信息不对"; cat /tmp/case-ssh-nokey.out 2>/dev/null || true; exit 1; }

# 3) 容器内现生成临时 key（只给本用例，不出容器、不碰生产）
timeout 30 $K8S_EXEC ssh-keygen -t ed25519 -N '' -f /tmp/e2e-tssh-key -q \
  || { echo "FAIL: 容器内 ssh-keygen 失败"; exit 1; }
timeout 30 $K8S_EXEC ssh-keygen -t ed25519 -N '' -f /tmp/e2e-tssh-key2 -q \
  || { echo "FAIL: 容器内 ssh-keygen 第二 key 失败"; exit 1; }

# 4) dry-run 固定选项：key-only 全家桶（BatchMode/禁密码/accept-new/超时/端口）
timeout 30 $K8S_EXEC env TSSH_KEY=/tmp/e2e-tssh-key tssh --dry-run somehost -- echo hi > /tmp/case-ssh-dry.out 2>&1 \
  || { echo "FAIL: tssh dry-run 失败"; cat /tmp/case-ssh-dry.out 2>/dev/null || true; exit 1; }
for opt in 'BatchMode=yes' 'PasswordAuthentication=no' 'KbdInteractiveAuthentication=no' 'PubkeyAuthentication=yes' 'IdentitiesOnly=yes' 'StrictHostKeyChecking=accept-new' 'ConnectTimeout=10' '-p 22' '/tmp/e2e-tssh-key'; do
  grep -q -- "$opt" /tmp/case-ssh-dry.out \
    || { echo "FAIL: dry-run 缺选项: $opt"; cat /tmp/case-ssh-dry.out || true; exit 1; }
done

# 5) -i 优先于 TSSH_KEY
timeout 30 $K8S_EXEC env TSSH_KEY=/tmp/e2e-tssh-key tssh -i /tmp/e2e-tssh-key2 --dry-run somehost -- uptime > /tmp/case-ssh-prio.out 2>&1 \
  || { echo "FAIL: tssh -i dry-run 失败"; cat /tmp/case-ssh-prio.out 2>/dev/null || true; exit 1; }
grep -q '/tmp/e2e-tssh-key2' /tmp/case-ssh-prio.out \
  || { echo "FAIL: -i 未生效"; cat /tmp/case-ssh-prio.out || true; exit 1; }

# 6) 超时/端口可配
timeout 30 $K8S_EXEC env TSSH_KEY=/tmp/e2e-tssh-key TSSH_CONNECT_TIMEOUT=7 tssh --dry-run somehost -- uptime > /tmp/case-ssh-timeout.out 2>&1 \
  || { echo "FAIL: TSSH_CONNECT_TIMEOUT dry-run 失败"; cat /tmp/case-ssh-timeout.out 2>/dev/null || true; exit 1; }
grep -q 'ConnectTimeout=7' /tmp/case-ssh-timeout.out \
  || { echo "FAIL: ConnectTimeout 未跟随 env"; cat /tmp/case-ssh-timeout.out || true; exit 1; }
timeout 30 $K8S_EXEC env TSSH_KEY=/tmp/e2e-tssh-key tssh -p 2222 --dry-run somehost -- uptime > /tmp/case-ssh-port.out 2>&1 \
  || { echo "FAIL: tssh -p dry-run 失败"; cat /tmp/case-ssh-port.out 2>/dev/null || true; exit 1; }
grep -q '\-p 2222' /tmp/case-ssh-port.out \
  || { echo "FAIL: -p 未生效"; cat /tmp/case-ssh-port.out || true; exit 1; }

# 7) 真连（两种靶，优先宿主）：
#    宿主靶 = fine-test.sh 在 runner 现起的 sshd，pod 侧 tssh 连过去 —— 这才是生产直连 .21 的形态。
#    无宿主靶（本地单跑）才回落容器内 127.0.0.1 loopback sshd。
if [ -n "${TSSH_HOST_BAIT:-}" ]; then
  BAIT_USER="$(printf '%s' "$TSSH_HOST_BAIT" | cut -d@ -f1)"
  BAIT_ADDR="$(printf '%s' "$TSSH_HOST_BAIT" | cut -d@ -f2)"
  BAIT_HOST="${BAIT_ADDR%:*}"
  BAIT_PORT="${BAIT_ADDR##*:}"
  [ -f "${TSSH_HOST_BAIT_KEY:-/nonexistent}" ] || { echo "FAIL: 宿主靶私钥缺失: ${TSSH_HOST_BAIT_KEY:-}"; exit 1; }
  # key 递进 pod（必须 -i：K8S_EXEC 不带 -i，缺了 stdin 会写出空文件 → libcrypto 报错）
  K8S_EXEC_I="kubectl exec -i -n ${K8S_NS:-opencode} deploy/${K8S_DEPLOY:?} -c ${K8S_CONTAINER:?} --"
  cat "$TSSH_HOST_BAIT_KEY" | $K8S_EXEC_I sh -c 'cat > /tmp/e2e-host-key && chmod 600 /tmp/e2e-host-key' \
    || { echo "FAIL: 宿主靶私钥递进 pod 失败"; exit 1; }
  # 传完必须非空且是 PEM 头（空文件只会在 ssh 侧报 libcrypto）
  $K8S_EXEC sh -c 'head -c 40 /tmp/e2e-host-key | grep -q "BEGIN OPENSSH PRIVATE KEY"' \
    || { echo "FAIL: 宿主靶私钥在 pod 内损坏/为空"; $K8S_EXEC wc -c /tmp/e2e-host-key 2>/dev/null || true; exit 1; }
  # 先等 pod → 宿主端口可达（20s）
  READY=0
  for _ in $(seq 1 20); do
    if $K8S_EXEC bash -c "exec 3<>/dev/tcp/$BAIT_HOST/$BAIT_PORT" >/dev/null 2>&1; then READY=1; break; fi
    sleep 1
  done
  [ "$READY" = "1" ] || { echo "FAIL: pod 20s 内连不上宿主靶 $BAIT_HOST:$BAIT_PORT（k3d 网桥路径？）"; exit 1; }
  timeout 40 $K8S_EXEC tssh -i /tmp/e2e-host-key -p "$BAIT_PORT" "$BAIT_USER@$BAIT_HOST" -- echo hello-tssh > /tmp/case-ssh-real.out 2>&1 \
    || { echo "FAIL: tssh 容器→宿主真连失败"; cat /tmp/case-ssh-real.out 2>/dev/null || true; \
         echo "--- 宿主 sshd 日志 ---"; sudo tail -20 "${TSSH_HOST_BAIT_KEY%/*}/sshd.log" 2>/dev/null || true; exit 1; }
  grep -q 'hello-tssh' /tmp/case-ssh-real.out \
    || { echo "FAIL: 容器→宿主回显不对"; cat /tmp/case-ssh-real.out || true; exit 1; }
  echo "CASE-INFO: 真连走宿主靶 $TSSH_HOST_BAIT（容器 → runner）"
else
  echo "CASE-INFO: 无宿主靶（TSSH_HOST_BAIT 未设），回落容器内 loopback"
  if ! $K8S_EXEC sh -c 'command -v sshd' >/dev/null 2>&1; then
    echo "CASE-INFO: 镜像无 sshd，apt 现装 openssh-server（仅测试容器，不进镜像）"
    timeout 120 $K8S_EXEC env DEBIAN_FRONTEND=noninteractive apt-get update -qq \
      || { echo "FAIL: apt update 失败"; exit 1; }
    timeout 300 $K8S_EXEC env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server \
      || { echo "FAIL: openssh-server 安装失败"; exit 1; }
  fi
  timeout 30 $K8S_EXEC sh -c 'mkdir -p /run/sshd /root/.ssh && chmod 700 /root/.ssh && ssh-keygen -A >/dev/null 2>&1; grep -qs "e2e-tssh-key" /root/.ssh/authorized_keys || cat /tmp/e2e-tssh-key.pub >> /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys' \
    || { echo "FAIL: sshd 起服准备失败（host key/authorized_keys）"; exit 1; }
  timeout 30 $K8S_EXEC sh -c 'nohup /usr/sbin/sshd -p 2222 -o ListenAddress=127.0.0.1 -o PasswordAuthentication=no >/tmp/e2e-sshd.log 2>&1 & echo $! > /tmp/e2e-sshd.pid' \
    || { echo "FAIL: sshd 启动失败"; $K8S_EXEC cat /tmp/e2e-sshd.log 2>/dev/null || true; exit 1; }
  READY=0
  for _ in $(seq 1 20); do
    if $K8S_EXEC bash -c '</dev/tcp/127.0.0.1/2222' >/dev/null 2>&1; then READY=1; break; fi
    sleep 1
  done
  [ "$READY" = "1" ] || { echo "FAIL: sshd 2222 端口 20s 未就绪"; $K8S_EXEC cat /tmp/e2e-sshd.log 2>/dev/null || true; exit 1; }
  timeout 30 $K8S_EXEC env TSSH_KEY=/tmp/e2e-tssh-key tssh -p 2222 127.0.0.1 -- echo hello-tssh > /tmp/case-ssh-real.out 2>&1 \
    || { echo "FAIL: tssh 真连 loopback 失败"; cat /tmp/case-ssh-real.out 2>/dev/null || true; exit 1; }
  grep -q 'hello-tssh' /tmp/case-ssh-real.out \
    || { echo "FAIL: 真连回显不对"; cat /tmp/case-ssh-real.out || true; exit 1; }
fi

# 8) 清理临时 key + 测试 sshd（尽力，不卡绿）
$K8S_EXEC sh -c 'kill "$(cat /tmp/e2e-sshd.pid 2>/dev/null)" 2>/dev/null; rm -f /tmp/e2e-tssh-key /tmp/e2e-tssh-key.pub /tmp/e2e-tssh-key2 /tmp/e2e-tssh-key2.pub /tmp/e2e-sshd.pid /tmp/e2e-host-key' >/dev/null 2>&1 || true

echo "CASE OK: case-ssh（help/缺 key/dry-run/真连俱在）"
