#!/bin/bash
# docker/erpnext/fine-test.sh — erpnext-cn 运行时细测（商家实现，骨架按固定约定调用）。
# 调用约定（bake-stack.yml 写死）：env 传 DIGEST / TEMP_TAG + K8S_NS / K8S_DEPLOY / K8S_CONTAINER；
# exit 0 + 打印 PASS 行即过，非零即红。
#
# 新预检：同货验证。骨架已在 k3d 里用 Flux 对完账（erpnext-cn digest 经 images 注入），本 hook 只做：
#   1) identity：k3d 里跑的必须是刚打出来的 digest（kubectl 读 deploy image）。
#   2) smoke：bench 可用 + nginx 配置合法（同镜像 bench 二进制 + nginx -t，无网无模型）。
#   3) link（E2E_CASES 非 skip 才跑）：带 Host 头打 nginx 8080 /login，200 即 nginx→gunicorn→mariadb→redis 全通；
#      带重试（建站 job 刚跑完的窗口），超时硬红。
set -euo pipefail

[ -n "${K8S_DEPLOY:-}" ] || { echo "FAIL: K8S_DEPLOY 为空（骨架 k8s_deploy_name 未传）"; exit 1; }
[ -n "${DIGEST:-}" ] || { echo "FAIL: DIGEST 为空（temp 推送未出 digest）"; exit 1; }
K8S_NS="${K8S_NS:-erpnext}"
K8S_CONTAINER="${K8S_CONTAINER:-nginx}"
K8S_EXEC="kubectl -n $K8S_NS exec deploy/$K8S_DEPLOY -c $K8S_CONTAINER --"
export K8S_NS K8S_DEPLOY K8S_CONTAINER

SITE="${ERPNext_SITE:-erp.xieyucheng.top}"

identity() { # 货对单：跑的必须是刚打出来的 digest
  local img
  img="$(kubectl -n "$K8S_NS" get "deploy/$K8S_DEPLOY" -o jsonpath='{.spec.template.spec.containers[0].image}')"
  [ -n "$img" ] || { echo "FAIL: deploy/$K8S_DEPLOY 读不到 image"; exit 1; }
  case "$img" in
    *"@${DIGEST}") echo "IDENTITY OK: deploy/$K8S_DEPLOY == $DIGEST" ;;
    *) echo "FAIL: deploy 跑的是 $img，不是刚打出来的 $DIGEST"; exit 1 ;;
  esac
}

smoke() { # 内置兜底：bench + nginx（快、无网、无模型）
  $K8S_EXEC bench --version \
    && echo "BENCH OK" || { echo "FAIL: bench 不可用"; exit 1; }
  $K8S_EXEC nginx -t 2>&1 \
    && echo "NGINX CONF OK" || { echo "FAIL: nginx -t 不过"; exit 1; }
  $K8S_EXEC fc-list :lang=zh | head -1 | grep -q . \
    && echo "CJK FONT OK" || { echo "FAIL: CJK 字体缺失（派生层没烘进）"; exit 1; }
  echo "E2E PASS: smoke"
}

link() { # 全链路：Host 头打 /login，200 即建站 + 全栈通
  local i code
  for i in $(seq 1 60); do
    code="$($K8S_EXEC curl -s -o /dev/null -w '%{http_code}' -H "Host: $SITE" http://localhost:8080/login || true)"
    if [ "$code" = "200" ]; then
      echo "LOGIN OK: $SITE/login -> 200"
      echo "E2E PASS: link（nginx→gunicorn→mariadb→redis 全通）"
      return 0
    fi
    sleep 5
  done
  echo "FAIL: 5min 内 $SITE/login 未 200（末次 $code），建站 job 或后端链异常"
  exit 1
}

identity
smoke
if [ "${E2E_CASES:-}" = "skip" ]; then
  echo "E2E SKIP: E2E_CASES=skip，只认 digest+版本+字体"
else
  link
fi

echo "FINE PASS: erpnext-cn 细测通过（k3d+Flux 同货，E2E_CASES: ${E2E_CASES:-<full>}）"
