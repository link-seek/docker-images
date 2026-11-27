# opencode-ops —— K3S 运维专用镜像线（派生自已稳定的 opencode-tools）
# 定位：单机（HW21 宿主 docker）维护台。继承 opencode-tools 的 glibc 底座、opencode v2 二进制、
#       全套云 CLI（kubectl/flux/hcloud/aliyun/oci/tailscale/gh/ssh/node/python）、以及烘焙的模型配置。
#       本线只补 ops 缺的 helm/k9s/stern/yq，并把 ops 入口/手册/技能烘进去。
# 版本：OPENTOOLS_TAG 由 dispatch 必填传入；此处默认值仅给本地构建兜底。
# 注意：不覆盖基底烘焙的 /root/.config/opencode/opencode.json（沿用它验证过的 litellm 网关配置），
#       只追加 AGENTS.md 与 skills，避免 ops 线与 tools 线的模型/插件配置漂移。
ARG OPENTOOLS_TAG=pin-required
FROM swr.cn-north-9.myhuaweicloud.com/link-seek/opencode-tools:${OPENTOOLS_TAG}

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
    curl -fsSL -o /usr/local/bin/stern "https://github.com/stern/stern/releases/download/v${STERN_VERSION}/stern_${STERN_VERSION}_linux_${A}" \
      && chmod +x /usr/local/bin/stern; \
    curl -fsSL -o /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${A}" \
      && chmod +x /usr/local/bin/yq; \
    helm version --short && stern --version && yq --version

# ops 手册 + 技能（追加，不覆盖基底 opencode.json）
COPY docker/opencode-ops/AGENTS.md /root/.config/opencode/AGENTS.md
COPY docker/opencode-ops/skills /root/.config/opencode/skills
COPY docker/opencode-ops/ops-entrypoint.sh /usr/local/bin/ops-entrypoint.sh
RUN chmod +x /usr/local/bin/ops-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/ops-entrypoint.sh"]
CMD ["serve", "--port", "4097", "--hostname", "0.0.0.0"]
