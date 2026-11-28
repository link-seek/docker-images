# opencode-ops —— K3S 运维专用镜像线（派生自已稳定的 opencode-tools）
# 定位：单机（HW21 宿主 docker）维护台。继承 opencode-tools 的 glibc 底座、opencode v2 二进制、
#       全套云 CLI（kubectl/flux/hcloud/aliyun/oci/tailscale/gh/ssh/node/python）、以及烘焙的模型配置。
#       不额外加 helm/k9s/stern/yq：它们的 Go 内嵌库带 CRITICAL CVE（Trivy 门禁不放行），
#       base 的 kubectl/flux 已覆盖运维需要（helm release 由 flux 管，日志用 kubectl logs）。
# 版本：底座 digest pin（不可变）。升级底座 = 改这一行发 PR（digest 即行为版本）；
#       别人把 :tag 挪走/重建 tools 线，都不会影响我们的构建结果。
FROM swr.cn-north-9.myhuaweicloud.com/link-seek/opencode-tools@sha256:e3ecd5a610158db70d8b512c2885def650f8dc3fcc2c58e8cfc94ac375309e16

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
