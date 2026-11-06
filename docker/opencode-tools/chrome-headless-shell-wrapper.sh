#!/bin/bash
# chrome-headless-shell wrapper：root 下自动加 --no-sandbox（Chrome 以 root 禁 sandbox，
# 不加直接拒绝启动，MCP check/export 即死于此）。OPEN_DESIGN_BROWSER_PATH 指到本文件；
# 真二进制在 .real。非 root 原样透传，不碰其它 flag。
if [ "$(id -u)" = "0" ]; then
  exec /usr/local/bin/chrome-headless-shell.real --no-sandbox "$@"
else
  exec /usr/local/bin/chrome-headless-shell.real "$@"
fi
