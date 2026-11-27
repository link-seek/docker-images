#!/bin/sh
# ops 入口：准备 kubeconfig / hcloud / ssh（复用宿主 mesh_id），再 exec opencode。
set -eu

# 1) kubeconfig：优先挂载 /etc/opencode-ops/kubeconfig，其次环境变量 KUBECONFIG_B64
mkdir -p /root/.kube
if [ -f /etc/opencode-ops/kubeconfig ]; then
  cp /etc/opencode-ops/kubeconfig /root/.kube/config
elif [ -n "${KUBECONFIG_B64:-}" ]; then
  echo "$KUBECONFIG_B64" | base64 -d > /root/.kube/config
fi
[ -f /root/.kube/config ] && chmod 600 /root/.kube/config

# 2) hcloud（KooCLI）——AK 运行时注入，不落盘镜像
if [ -n "${HCLOUD_AK:-}" ]; then
  yes | hcloud configure set --cli-access-key="${HCLOUD_AK}" --cli-secret-key="${HCLOUD_SK:-}" \
        --cli-region="${HCLOUD_REGION:-cn-north-4}" >/dev/null 2>&1 || true
  sed -i 's/"agreePrivacy": "false"/"agreePrivacy": "true"/' /root/.hcloud/config.json 2>/dev/null || true
fi

# 3) 模型 key：env 没给就从集群现存 Secret 兜底（需 kubectl 已就绪）
if [ -z "${LITELLM_API_KEY:-}" ] && [ -f /root/.kube/config ]; then
  LITELLM_API_KEY="$(kubectl -n opencode-xieyucheng get secret opencode-xieyucheng-env \
    -o jsonpath='{.data.LITELLM_API_KEY}' 2>/dev/null | base64 -d || true)"
  [ -n "$LITELLM_API_KEY" ] && export LITELLM_API_KEY
fi

# 4) SSH：复用宿主 mesh_id（systemd 从宿主 /root/.ssh/mesh_id 挂到 /etc/opencode-ops/mesh_id）
mkdir -p /root/.ssh && chmod 700 /root/.ssh
if [ -f /etc/opencode-ops/mesh_id ]; then
  cp /etc/opencode-ops/mesh_id /root/.ssh/mesh_id && chmod 600 /root/.ssh/mesh_id
  printf '%s\n' 'Host 192.168.1.* 100.* 127.0.0.1' '  IdentityFile /root/.ssh/mesh_id' \
    '  StrictHostKeyChecking no' '  UserKnownHostsFile /dev/null' > /root/.ssh/config
  chmod 600 /root/.ssh/config
fi

# 5) workspace git 身份（默认值，可被 env 覆盖）
git config --global user.name  "${GIT_AUTHOR_NAME:-opencode-ops}" 2>/dev/null || true
git config --global user.email "${GIT_AUTHOR_EMAIL:-opencode-ops@local}" 2>/dev/null || true

exec opencode "$@"
