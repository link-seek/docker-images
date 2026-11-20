#!/bin/sh
# team 线 gh 护栏：只允许 `gh issue create`（另放行 --help / --version / version / auth status）。
# 目的：防止 agent 误操作 GitHub。注意：token 未降权，这是护栏不是安全边界——
# 直接调 /usr/local/libexec/gh-real，或用 $GH_TOKEN 自行发 HTTP 请求，都能绕过。
set -eu

REAL=/usr/local/libexec/gh-real

deny() {
  cat >&2 <<'EOF'
[gh-restrict] 本容器只允许：gh issue create
其余 gh 命令（api / pr / workflow / repo / release 等）已被策略拒绝。
需要别的 GitHub 操作请走 CI 流水线或人工处理。
EOF
  exit 1
}

[ -x "$REAL" ] || { echo "[gh-restrict] 缺少真二进制 $REAL" >&2; exit 127; }
[ "$#" -gt 0 ] || deny

case "$1" in
  --help|-h|--version|version)
    exec "$REAL" "$@"
    ;;
  auth)
    [ "${2:-}" = "status" ] || deny
    exec "$REAL" auth status
    ;;
  issue)
    [ "${2:-}" = "create" ] || deny
    exec "$REAL" "$@"
    ;;
  *)
    deny
    ;;
esac
