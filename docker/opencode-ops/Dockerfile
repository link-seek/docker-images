# opencode-ops —— K3S 运维专用镜像线（派生自已稳定的 opencode-tools）
# 定位：单机（HW21 宿主 docker）维护台。继承 opencode-tools 的 glibc 底座、opencode v2 二进制、
#       全套云 CLI（kubectl/flux/hcloud/aliyun/oci/tailscale/gh/ssh/node/python）、以及烘焙的模型配置。
#       本线只补 ops 缺的 helm/k9s/stern/yq，并把 ops 入口/手册/技能烘进去。
# 版本：底座按 digest 钉死（不可变）。要升级底座 = 主动改下面这行（或 dispatch 传 OPENTOOLS_IMAGE）；
#       别人把 :tag 挪走/重建 tools 线，都不会影响我们重新构建的结果。
ARG OPENTOOLS_IMAGE=swr.cn-north-9.myhuaweicloud.com/link-seek/opencode-tools@sha256:e3ecd5a610158db70d8b512c2885def650f8dc3fcc2c58e8cfc94ac375309e16
FROM ${OPENTOOLS_IMAGE}

ARG HELM_VERSION=3.16.4
ARG K9S_VERSION=0.32.7
ARG STERN_VERSION=1.30.0
ARG YQ_VERSION=4.44.3

# 追加 ops 常用 CLI
RUN set -eux; ARCH="$(uname -m)"; case "$ARCH" in \
      x86_64) A=amd64;; aarch64) A=arm64;; *) echo "unsupported arch $ARCH"; exit 1;; esac; \
    curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${A}.tar.gz" | tar -xz -C /tmp \
      && mv "/tmp/linux-${A}/helm" /usr/local/bin/helm && rm -rf "/tmp/linux-${A}"; \
    curl -fsSL -o /tmp/k9s.tgz "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_Linux_${A}.tar.gz" \
      && tar -xzf /tmp/k9s.tgz -C /usr/local/bin k9s && rm -f /tmp/k9s.tgz; \
    curl -fsSL -o /tmp/stern.tgz "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_${A}.tar.gz" \
      && tar -xzf /tmp/stern.tgz -C /usr/local/bin stern && rm -f /tmp/stern.tgz; \
    curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${A}" \
      && chmod +x /usr/local/bin/yq; \
    helm version --short && stern --version && yq --version

# 本地长期记忆：opencode-mem（tickernelz）。版本单源头 = 本 ARG，注入 opencode.json 后安装。
ARG OPENCODE_MEM_VERSION=2.41.1
COPY docker/opencode-ops/opencode.json /root/.config/opencode/opencode.json
COPY docker/opencode-ops/opencode-mem.jsonc /root/.config/opencode/opencode-mem.jsonc
RUN sed -i "s/__OPENCODE_MEM_VERSION__/${OPENCODE_MEM_VERSION}/" /root/.config/opencode/opencode.json \
 && grep -q "\"opencode-mem@${OPENCODE_MEM_VERSION}\"" /root/.config/opencode/opencode.json \
 && opencode plugin add "opencode-mem@${OPENCODE_MEM_VERSION}" \
 && npm cache clean --force && rm -rf /root/.npm /tmp/opencode-* 2>/dev/null; opencode --version

# ops 手册 + 技能
COPY docker/opencode-ops/AGENTS.md /root/.config/opencode/AGENTS.md
COPY docker/opencode-ops/skills /root/.config/opencode/skills
COPY docker/opencode-ops/ops-entrypoint.sh /usr/local/bin/ops-entrypoint.sh
RUN chmod +x /usr/local/bin/ops-entrypoint.sh

# OpenCode 默认项目目录；配合 /workspace 的 git init，worktree 功能可用
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/ops-entrypoint.sh"]
CMD ["serve", "--port", "4097", "--hostname", "0.0.0.0"]
