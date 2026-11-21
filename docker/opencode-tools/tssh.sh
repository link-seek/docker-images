#!/bin/sh
# tssh：ssh 直连薄包装（key-only，免 pty 喂密码）。
# 背景：容器直连生产主机只有 key（容器外挂载），shell 工具做不了交互；
# 以前靠 python pty 喂密码，笨且密码进内存。本包装强制 key 登录，无 key 直接报错，
# 绝不回落密码（BatchMode + PasswordAuthentication=no）。
#
# 用法：
#   tssh [--help] [-i <key>] [-p <port>] [--dry-run] <host> [--] <cmd...>
#   TSSH_KEY=<key> tssh <host> -- <cmd...>
#
# 环境变量（都不进镜像，由挂载/env 注入）：
#   TSSH_KEY              私钥路径（默认 ~/.ssh/id_hw21；-i 优先于它）
#   TSSH_PORT             远端端口（默认 22；-p 优先于它）
#   TSSH_CONNECT_TIMEOUT  建连超时秒（默认 10）
#   TSSH_DRY_RUN=1        只打印 ssh 命令行，不真连（给 goss/e2e 断言用）
#
# 约定（与现有流水线一致）：
#   BatchMode=yes + PasswordAuthentication=no + KbdInteractiveAuthentication=no
#   + PubkeyAuthentication=yes + IdentitiesOnly=yes
#   + StrictHostKeyChecking=accept-new + ConnectTimeout=${TSSH_CONNECT_TIMEOUT:-10}
set -eu

usage() {
  cat <<'EOF'
用法：
  tssh [-i <key>] [-p <port>] [--dry-run] <host> [--] <cmd...>

直连生产主机的 key-only ssh 薄包装，无 key 直接报错，不回落密码。
key 路径：-i > $TSSH_KEY > ~/.ssh/id_hw21（容器外挂载，私钥不进镜像）。
端口默认 22（-p > $TSSH_PORT）；其余与 ssh 一致。
示例：
  tssh hw21 -- uptime
  tssh -i ~/.ssh/id_other user@host -- systemctl status k3s
  TSSH_KEY=~/.ssh/id_other tssh host -- uptime
  tssh --dry-run host -- uptime   # 只打印 ssh 命令行，不断言连通
EOF
}

KEY_FLAG=""
PORT_FLAG=""
DRY_RUN="${TSSH_DRY_RUN:-0}"

# --- 选项解析（只认 -i/--dry-run/--help，其余原样留给 host/cmd） ---
while [ "$#" -gt 0 ]; do
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    -i)
      [ "$#" -ge 2 ] || { echo "tssh: -i 缺私钥路径" >&2; exit 2; }
      KEY_FLAG="$2"
      shift 2
      ;;
    -p)
      [ "$#" -ge 2 ] || { echo "tssh: -p 缺端口" >&2; exit 2; }
      PORT_FLAG="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "tssh: 未知选项: $1（看 tssh --help）" >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

HOST="${1:-}"
[ -n "$HOST" ] || { echo "tssh: 缺少 <host>（看 tssh --help）" >&2; exit 2; }
shift
# 允许 `tssh host -- cmd` 的 `--` 分隔；没有也不强求
if [ "${1:-}" = "--" ]; then
  shift
fi
[ "$#" -gt 0 ] || { echo "tssh: 缺少远程命令（看 tssh --help）" >&2; exit 2; }

# key 路径：-i > TSSH_KEY > 默认
if [ -n "$KEY_FLAG" ]; then
  KEY="$KEY_FLAG"
elif [ -n "${TSSH_KEY:-}" ]; then
  KEY="$TSSH_KEY"
else
  KEY="${HOME:-/root}/.ssh/id_hw21"
fi

[ -n "$KEY" ] || { echo "tssh: key 路径为空" >&2; exit 2; }
[ -f "$KEY" ] && [ -r "$KEY" ] || {
  echo "tssh: 缺少私钥: $KEY（容器外挂载，私钥不进镜像；-i 或 \$TSSH_KEY 指定）" >&2
  exit 2
}

command -v ssh >/dev/null 2>&1 || { echo "tssh: 镜像缺 ssh（需重打包含 openssh-client 的 tools 镜像）" >&2; exit 127; }

if [ -n "$PORT_FLAG" ]; then
  PORT="$PORT_FLAG"
else
  PORT="${TSSH_PORT:-22}"
fi
case "$PORT" in
  ''|*[!0-9]*) echo "tssh: 端口非法: $PORT" >&2; exit 2 ;;
esac

TIMEOUT="${TSSH_CONNECT_TIMEOUT:-10}"

# dry-run：打印最终 ssh 命令行（单行，goss/e2e 用 grep 断言固定选项）
if [ "$DRY_RUN" = "1" ]; then
  printf 'ssh'
  printf ' %s' -p "$PORT" -i "$KEY"
  printf ' %s' -o "BatchMode=yes" -o "PasswordAuthentication=no" -o "KbdInteractiveAuthentication=no" \
    -o "PubkeyAuthentication=yes" -o "IdentitiesOnly=yes" \
    -o "StrictHostKeyChecking=accept-new" -o "ConnectTimeout=$TIMEOUT"
  printf ' %s' "$HOST" "$@"
  printf '\n'
  exit 0
fi

exec ssh -p "$PORT" -i "$KEY" \
  -o BatchMode=yes \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o PubkeyAuthentication=yes \
  -o IdentitiesOnly=yes \
  -o StrictHostKeyChecking=accept-new \
  -o "ConnectTimeout=$TIMEOUT" \
  -- "$HOST" "$@"
