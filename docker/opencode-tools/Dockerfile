# opencode-tools（glibc 线）：官方 opencode 二进制 + 自研工具层 + 记忆插件烘焙
# 用法：docker build --build-arg OPENCODE_TAG=<版本> -f docker/opencode-tools/Dockerfile -t <镜像> .
# 背景：官方 ghcr.io/anomalyco/opencode 镜像是 Alpine/musl，原生件兼容性差。
# 此文件改走 ubuntu:24.04 + 官方 release 二进制（opencode.ai/files/bin，非 GHCR）。
# 二进制版本线：v2 tag 有 release 资产（x64/arm64，x64 取 baseline 最大兼容，随 brew 配方）。
# 版本 pin：OPENCODE_TAG（dispatch 传参）+ opencode-cognee（只 Dockerfile 的 ARG 一处定义，构建时注入 jsonc，见下）。
# 注意：CI 全按 dispatch 必填参数构建，从不读这里的默认值；默认值只给本地 docker build 兜底。
# 审计靠 bake run 日志（tag/digest），不在仓里记版本。
ARG OPENCODE_TAG=2.3.0

# --- open-design MCP server 从 git main 构建（含 PR #114「远程 CDP 浏览器」能力；npm 最新 0.4.0 未含）---
# 产物 out/index.js 由 esbuild 打成自包含 CJS（core + puppeteer-core 全 bundle），
# 仅 content/sdk 两个外部依赖随 npm install 拉；构建独立放在 builder 阶段，不污染最终镜像层。
# 版本 pin：ODK_REF（单源头）；bump=改这行发 PR。
# digest-exempt: builder-stage（编译期，不发布）
FROM node:22-bookworm-slim@sha256:170fab707454b1350981adcdc2f536ec21f24d06d7f008e8d40064afeacb8a94 AS odk-builder
ARG ODK_REF=fcf21f35113a4d0ea116b4d50e2251b0c52fc8bd
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
# 远程浏览器渲染修复（源码覆盖）：上游 startStaticServer 只绑 127.0.0.1，独立 Pod 的 browserless
# 访问不到本 Pod loopback → check/export 渲染白页。用本仓覆盖文件：存在 OPEN_DESIGN_BROWSER_URL 时
# 绑 0.0.0.0 且 baseUrl 用可达地址（Pod IP），本地浏览器模式仍 127.0.0.1。
COPY docker/_shared/staticServer.ts /tmp/staticServer.override.ts
RUN git clone https://github.com/feimacode/open-design-agent-kit /src \
 && cd /src && git checkout "${ODK_REF}" \
 && cp /tmp/staticServer.override.ts /src/packages/core/src/export/staticServer.ts \
 && npm ci --no-audit --no-fund \
 && npm run compile -w packages/mcp-server \
 && mkdir -p /out && npm pack -w packages/mcp-server --pack-destination /out \
 && cp -a /src/.agents/skills/open-design /out/open-design-skill

# 底座 digest pin（2026-10-18，ubuntu 24.04 当日最新 manifest list，不断 arm 兼容）。
# 行为=digest：重打即刷新底座；bump=改这行发 PR。
FROM ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac

USER root
SHELL ["/bin/bash", "-c"]

# 安全基线（Trivy 门）：底座 digest 自带 apt 旧版，noble-updates 已有高危修复（CVE-2026-109518）；
# 定向 --only-upgrade 这两包，不全量 upgrade（减少漂移面）。
RUN apt-get update && apt-get install -y --no-install-recommends --only-upgrade apt libapt-pkg6.0t64 \
 && rm -rf /var/lib/apt/lists/* \
 && apt --version

# 基础运行时（放最前：裸 ubuntu 连 curl 都没有，后面所有下载都靠它）：
# node22（npx/wrangler/agent-browser 要 node>=22，Ubuntu 自带 node18 不可用，
# 走 NodeSource，与 Dockerfile.runner 同 pattern）+ python+pip + git + ssh(+sshpass) + msmtp + gnupg
# sshpass 走密码认证（目标机只有密码、没铺 key 时用）；只在 universe，底座默认源已含。
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git python3 python3-pip openssh-client sshpass msmtp gnupg \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
 && git --version && ssh -V && sshpass -V && node --version && msmtp --version

# openssh-server：单独一层（避免撑大基础层超"单层体积门"），并清掉安装时生成的 host 私钥
# （运行时在 /root/.ssh/sshd 现生成；否则 Trivy 密钥扫描会把 baked 私钥判成 HIGH secret）。
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server \
 && rm -rf /var/lib/apt/lists/* \
 && rm -f /etc/ssh/ssh_host_* \
 && command -v sshd

# opencode 官方二进制（glibc 版；musl 版另有 -musl 后缀，不要拿错）
# x64 取 baseline（随 brew 配方，最大 CPU 兼容）；arm64 无 baseline 变体
ARG OPENCODE_TAG
RUN ARCH="$(uname -m)"; case "$ARCH" in \
      x86_64) BIN_ARCH=x64-baseline;; \
      aarch64) BIN_ARCH=arm64;; \
      *) echo "unsupported arch $ARCH" && exit 1;; \
    esac \
 && curl -fsSL -o /tmp/opencode.tar.gz \
      "https://opencode.ai/files/bin/${OPENCODE_TAG}/opencode-linux-${BIN_ARCH}.tar.gz" \
 && tar -xzf /tmp/opencode.tar.gz -C /tmp \
 && mv /tmp/opencode /usr/local/bin/opencode \
 && chmod +x /usr/local/bin/opencode \
 && rm -f /tmp/opencode.tar.gz \
 && opencode --version

# （基础运行时已在上一步装好：curl/git/python/ssh/msmtp/node，供下面各工具下载校验）

# 版本 pin（沿用 Dockerfile.tools 验证过的版本）
ARG GH_VERSION=2.103.3
ARG ALIYUN_VERSION=3.5.2
ARG OCI_SPEC=oci-cli==3.97.1
ARG AGENT_BROWSER_VERSION=0.41.0
ARG TAILSCALE_VERSION=1.102.4
ARG KUBECTL_VERSION=1.37.2
ARG FLUX_VERSION=2.10.0

# gh：官方 tarball（Go 静态二进制）
RUN ARCH="$(uname -m)"; case "$ARCH" in x86_64) GH_ARCH=amd64;; aarch64) GH_ARCH=arm64;; *) echo "unsupported arch $ARCH" && exit 1;; esac \
 && curl -fsSL -o /tmp/gh.tar.gz \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz" \
 && tar -xzf /tmp/gh.tar.gz -C /tmp \
 && mv "/tmp/gh_${GH_VERSION}_linux_${GH_ARCH}/bin/gh" /usr/local/bin/gh \
 && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_${GH_ARCH}" \
 && gh --version

# aliyun CLI v3：官方 tarball
RUN ARCH="$(uname -m)"; case "$ARCH" in x86_64) ALIYUN_ARCH=amd64;; aarch64) ALIYUN_ARCH=arm64;; *) echo "unsupported arch $ARCH" && exit 1;; esac \
 && curl -fsSL -o /tmp/aliyun.tgz \
      "https://github.com/aliyun/aliyun-cli/releases/download/v${ALIYUN_VERSION}/aliyun-cli-linux-${ALIYUN_VERSION}-${ALIYUN_ARCH}.tgz" \
 && tar -xzf /tmp/aliyun.tgz -C /tmp \
 && mv /tmp/aliyun /usr/local/bin/aliyun \
 && rm -f /tmp/aliyun.tgz \
 && aliyun --version

# hcloud（华为云 KooCLI）：官方 OBS latest 直链
RUN ARCH="$(uname -m)"; case "$ARCH" in x86_64) HCLOUD_ARCH=amd64;; aarch64) HCLOUD_ARCH=arm64;; *) echo "unsupported arch $ARCH" && exit 1;; esac \
 && curl -fsSL -o /tmp/hcloud.tgz \
      "https://ap-southeast-3-hwcloudcli.obs.ap-southeast-3.myhuaweicloud.com/cli/latest/huaweicloud-cli-linux-${HCLOUD_ARCH}.tar.gz" \
 && tar -xzf /tmp/hcloud.tgz -C /tmp \
 && mv /tmp/hcloud /usr/local/bin/hcloud \
 && rm -f /tmp/hcloud.tgz \
 && printf 'y\n' | hcloud version

# oci-cli + markitdown：pip（Oracle/微软官方 PyPI）
# certifi 钉死（CVE GHSA-6q48：旧版 bundle 已沦陷中间 CA，Trivy CRITICAL 门）
RUN pip3 install --no-cache-dir --break-system-packages "${OCI_SPEC}" "certifi==2026.10.23" \
 && oci --version
RUN pip3 install --no-cache-dir --break-system-packages markitdown==0.1.9 \
 && markitdown --version

# crypto 后升层（与 oci-cli 的上古 pin 解耦）：CVE-2026-26007 等要求新版；
# oci-cli 若 import 已删 API 会在这里冒烟失败，届时改白名单认，不硬升。
RUN pip3 install --no-cache-dir --break-system-packages --upgrade "cryptography==50.0.2" "pyOpenSSL==26.4.0" \
 && python3 -c "import cryptography, OpenSSL; print('crypto-ok', cryptography.__version__)" \
 && oci --version

# wrangler + agent-browser + lmnr-cli：npm 全局
RUN npm install -g wrangler@4.167.0 \
 && wrangler --version \
 && npm cache clean --force && rm -rf /root/.npm
RUN npm install -g "agent-browser@${AGENT_BROWSER_VERSION}" lmnr-cli \
 && agent-browser --version \
 && npm cache clean --force && rm -rf /root/.npm

# 设计能力（feimacode/open-design-agent-kit，社区包）：
# - skill：从 odk-builder（ODK_REF 固定）直接 COPY，构建期不再 npx 联网拉浮动 main。
# - MCP server：从 ODK_REF 构建安装。
# - 版本 pin：ODK_REF（单源头）；bump=改那一行发 PR。
COPY --from=odk-builder /out/open-design-skill /root/.agents/skills/open-design
COPY --from=odk-builder /out/feimacode-open-design-agent-kit-mcp-*.tgz /tmp/odk-mcp.tgz
RUN npm install -g /tmp/odk-mcp.tgz \
 && command -v open-design-mcp \
 && timeout 25 open-design-mcp --help \
 && rm -f /tmp/odk-mcp.tgz \
 && npm cache clean --force && rm -rf /root/.npm /tmp/*

# tailscale：官方静态二进制（tailscale + tailscaled；userspace 模式无需 /dev/net/tun / NET_ADMIN）
RUN ARCH="$(uname -m)"; case "$ARCH" in x86_64) TS_ARCH=amd64;; aarch64) TS_ARCH=arm64;; *) echo "unsupported arch $ARCH" && exit 1;; esac \
 && curl -fsSL -o /tmp/tailscale.tgz \
      "https://pkgs.tailscale.com/stable/tailscale_${TAILSCALE_VERSION}_${TS_ARCH}.tgz" \
 && tar -xzf /tmp/tailscale.tgz -C /tmp \
 && mv "/tmp/tailscale_${TAILSCALE_VERSION}_${TS_ARCH}/tailscale" /usr/local/bin/tailscale \
 && mv "/tmp/tailscale_${TAILSCALE_VERSION}_${TS_ARCH}/tailscaled" /usr/local/bin/tailscaled \
 && rm -rf /tmp/tailscale.tgz "/tmp/tailscale_${TAILSCALE_VERSION}_${TS_ARCH}" \
 && tailscale version

# kubectl：官方 release 二进制（breakglass/排障常驻；与集群版本对齐）
RUN ARCH="$(uname -m)"; case "$ARCH" in x86_64) KUBECTL_ARCH=amd64;; aarch64) KUBECTL_ARCH=arm64;; *) echo "unsupported arch $ARCH" && exit 1;; esac \
 && curl -fsSLo /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl" \
 && chmod +x /usr/local/bin/kubectl \
 && kubectl version --client

# flux：官方 GitHub release 二进制（与控制器 v2.10.0 同版；自验 rollout 去 HW21 跳板）
RUN ARCH="$(uname -m)"; case "$ARCH" in x86_64) FLUX_ARCH=amd64;; aarch64) FLUX_ARCH=arm64;; *) echo "unsupported arch $ARCH" && exit 1;; esac \
 && curl -fsSL -o /tmp/flux.tar.gz \
      "https://github.com/fluxcd/flux2/releases/download/v${FLUX_VERSION}/flux_${FLUX_VERSION}_linux_${FLUX_ARCH}.tar.gz" \
 && tar -xzf /tmp/flux.tar.gz -C /tmp \
 && mv /tmp/flux /usr/local/bin/flux \
 && chmod +x /usr/local/bin/flux \
 && rm -f /tmp/flux.tar.gz \
 && flux --version

# kit 的 check/export 走远程浏览器（CDP；上游 #114 已合；feimacode/open-design-agent-kit）。
# 接线：OPEN_DESIGN_BROWSER_URL（DevTools HTTP endpoint，如 http://browserless.<ns>.svc:3000，
# 部署侧由 puppeteer.connect({browserURL}) 读取 /json/version 后连其 webSocketDebuggerUrl）。
# 本地 chrome 已删（-450M）；无远程浏览器可用的环境不再支持设计 e2e。
# 部署侧必须保证 browserless 可达且其 EXTERNAL 指向可路由地址（否则 /json/version 返回 ws://0.0.0.0 连不上）。

# 非涉密默认配置烘入镜像（各机器行为一致；密钥仍走 env/挂载，不进镜像）：
# - opencode.jsonc：模型走 LiteLLM 网关 + plugins pin 死 opencode-cognee
# - AGENTS.md：agent 使用说明（含记忆系统规约）
# 注意：部署侧不要再挂载这些文件，否则会盖住烘入的版本。
# 注意：源文件叫 opencode.jsonc（保留注释），但必须落盘为 opencode.json——
# 2.1.4 实测 daemon 只读 opencode.json，.jsonc 同内容零命中（debug config 0 结果）。
COPY docker/opencode-tools/AGENTS.md /root/.config/opencode/
COPY docker/opencode-tools/opencode.jsonc /root/.config/opencode/opencode.json
# opencode-cognee 插件烘入（纯 TS，零 runtime 依赖；每用户数据集 + REST）。
# 单源头落位：ARG 是唯一版本号来源——先把 jsonc 占位符注入成实值（注入失败直接红），再按同一值 install。
# 该包只发布在 GitHub tag（npm scope 暂不可用）；npm 会把 GitHub 包改写成 ssh，先强制 https。
ARG OPENCODE_COGNEE_VERSION=0.2.2
RUN git config --global url.https://github.com/.insteadOf ssh://git@github.com/ \
 && git config --global --add url.https://github.com/.insteadOf git@github.com: \
 && sed -i "s/__OPENCODE_COGNEE_VERSION__/${OPENCODE_COGNEE_VERSION}/" /root/.config/opencode/opencode.json \
 && grep -q "@linkseek/opencode-cognee@${OPENCODE_COGNEE_VERSION}" /root/.config/opencode/opencode.json \
 && opencode plugin add "github:link-seek/opencode-cognee#v${OPENCODE_COGNEE_VERSION}" \
 && npm cache clean --force && rm -rf /root/.npm /tmp/opencode-* 2>/dev/null; opencode --version
# - send-mail：msmtp 薄包装（配置全走 SMTP_* 环境变量）
# - fetch-mail：IMAP 只读薄客户端（标准库 imaplib；IMAP_* 缺省回落 SMTP_*，163 收发共用授权码）
# - md2html：send-mail -m 用的 markdown→HTML 转换（烘焙依赖 markdown+premailer，见下）
COPY docker/_shared/send-mail.sh /usr/local/bin/send-mail
COPY docker/_shared/fetch-mail.py /usr/local/bin/fetch-mail
COPY docker/_shared/md2html.py /usr/local/lib/send-mail/md2html.py
COPY docker/opencode-tools/tssh.sh /usr/local/bin/tssh
# send-mail -m 烘焙依赖（社区标准配方；goss 转换冒烟不过则不发版）
ARG MD_DEPS="markdown==3.7 premailer==3.10.0"
RUN pip3 install --no-cache-dir --break-system-packages $MD_DEPS \
 && python3 -c "import markdown, premailer; print('md-ok')"
RUN chmod +x /usr/local/bin/send-mail /usr/local/bin/fetch-mail /usr/local/bin/tssh && send-mail --help >/dev/null \
 && fetch-mail --help >/dev/null \
 && tssh --help >/dev/null \
 && echo "tools image ready:" && opencode --version
# 默认直接 serve（compose 仍可用 entrypoint 覆盖；CI 可直接 docker run 起服）
ENTRYPOINT ["opencode"]
CMD ["serve", "--port", "4097", "--hostname", "0.0.0.0"]
