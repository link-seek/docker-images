# opencode-tools（glibc 线）：官方 opencode 二进制 + 自研工具层 + 记忆插件烘焙
# 用法：docker build --build-arg OPENCODE_TAG=<版本> -f docker/opencode-tools/Dockerfile -t <镜像> .
# 背景：官方 ghcr.io/anomalyco/opencode 镜像是 Alpine/musl，opencode-mem 的
# onnxruntime/turso 原生件缺 fcntl64 起不来（实测）。此文件改走 ubuntu:24.04 +
# 官方 release 二进制（opencode.ai/files/bin，非 GHCR），glibc 全兼容。
# 二进制版本线：v2 tag 有 release 资产（x64/arm64，x64 取 baseline 最大兼容，随 brew 配方）。
# 版本 pin：OPENCODE_TAG（dispatch 传参）+ opencode-mem（全局 ARG 单源头，各 stage 内 bare 重声明继承；
# 构建时注入 jsonc，见下）。
# 注意：CI 全按 dispatch 必填参数构建，从不读这里的默认值；默认值只给本地 docker build 兜底。
# 审计靠 bake run 日志（tag/digest），不在仓里记版本。
ARG OPENCODE_TAG=2.3.0
ARG OPENCODE_MEM_VERSION=2.41.1

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

# --- opencode-mem 插件烘焙（builder 分块：单层体积门 500MB，~1.3G 缓存拆 5 个 COPY 层）---
# 背景：`opencode plugin add` 一次写下 ~1.3G（onnxruntime/turso natives 大头），单层必超门限；
# 跨洋按 blob 传，小 blob 断流重试代价小，拆分符合门限本意。总量与布局与 plugin add 产物一致。
# loader 按 <name>@<version>/<ts>/ 扫描单目录（见 #525 讨论），builder 内归一化时间戳为 0；
# goss mem-plugin-tree/mem-plugin-loaded 双重验证（入口文件 + plugin check 报 current）。
# 版本 pin：全局 ARG OPENCODE_MEM_VERSION（单源头）；bump=改文件头那一行发 PR。
# 分块（2.41.1 实测 MB 值；bump 插件版本后若门限红，按体积重切 c1..c5；c5=剩余物自动兜底）：
# c1 onnxruntime-node ~294 / c2 @huggingface+effect ~353 / c3 @opencode ~326 /
# c4 onnxruntime-web + 中小件 ~280 / c5 其余 ~100。
# digest-exempt: builder-stage（编译期，不发布；底座与最终镜像同 digest，有变更两处同步改）。
FROM ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac AS mem-builder
ARG OPENCODE_TAG
ARG OPENCODE_MEM_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates nodejs npm \
 && rm -rf /var/lib/apt/lists/* \
 && node --version && npm --version
# opencode 二进制（与最终镜像同版本同源；只用于 builder 内 plugin add，不进最终镜像）
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
# 插件安装（行为与原最终镜像 RUN 一字不差；config 缺省由 add 自动创建，builder 产物只取缓存树）
COPY docker/opencode-tools/opencode.jsonc /root/.config/opencode/opencode.json
RUN opencode plugin add "opencode-mem@${OPENCODE_MEM_VERSION}" \
 && STAGE="/root/.cache/opencode/npm/opencode-mem@${OPENCODE_MEM_VERSION}" \
 && TS="$(ls "$STAGE")" && [ -n "$TS" ] && [ "$(echo "$TS" | wc -l)" = "1" ] \
 && mv "$STAGE/$TS" "$STAGE/0" \
 && cd "$STAGE/0" \
 && mkdir -p /mem/c1 /mem/c2 /mem/c3 /mem/c4 /mem/c5 \
 && mv node_modules/onnxruntime-node /mem/c1/ \
 && mv node_modules/@huggingface node_modules/effect /mem/c2/ \
 && mv node_modules/@opencode /mem/c3/ \
 && for d in onnxruntime-web @img @opentelemetry @libsql @tursodatabase @redis @smithy zod web-streams-polyfill @aws-sdk @opencode-ai; do mv "node_modules/$d" /mem/c4/ 2>/dev/null || true; done \
 && mv package.json package-lock.json node_modules /mem/c5/ \
 && for d in /mem/c1 /mem/c2 /mem/c3 /mem/c4 /mem/c5; do s=$(du -sm "$d" | cut -f1); [ "$s" -lt 450 ] || { echo "chunk too big: $d ${s}MB（门限 500，留 50 余量；重切分块）"; exit 1; }; done \
 && du -sh /mem/c* \
 && leftovers="$(ls -A "$STAGE/0" 2>/dev/null)" && [ -z "$leftovers" ] || { echo "unpack split leftover: $leftovers"; exit 1; }

# 底座 digest pin（2026-10-18，ubuntu 24.04 当日最新 manifest list，不断 arm 兼容）。
# 行为=digest：重打即刷新底座；bump=改这行发 PR（mem-builder 底座同步改，保持同源）。
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
# oci-cli pin 回退到 3.96.3：3.97.0 依赖的 oci==2.192.1 从未发布到 PyPI
#（只有 2.192.0/2.193.0），上游打包事故，装即红；等 Oracle 修好再跟进。
ARG OCI_SPEC=oci-cli==3.96.3
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
# - opencode.jsonc：模型走 LiteLLM 网关 + plugins pin 死 opencode-mem
# - opencode-mem.jsonc：记忆插件配置（storagePath 钉 prod-data 卷，密钥全走 env://）
# - AGENTS.md：agent 使用说明（含记忆系统规约）
# 注意：部署侧不要再挂载这些文件，否则会盖住烘入的版本。
# 注意：源文件叫 opencode.jsonc（保留注释），但必须落盘为 opencode.json——
# 2.1.4 实测 daemon 只读 opencode.json，.jsonc 同内容零命中（debug config 0 结果）。
COPY docker/_shared/opencode-mem.jsonc /root/.config/opencode/
COPY docker/opencode-tools/AGENTS.md /root/.config/opencode/
COPY docker/opencode-tools/opencode.jsonc /root/.config/opencode/opencode.json
# opencode-mem 插件本体烘焙（~1.3G 缓存；单层体积门 500MB，mem-builder 拆 5 块 COPY，每块 <450MB）。
# - 布局与 plugin add 产物一致（时间戳目录归一化为 0；loader 扫描单目录，goss mem-plugin-loaded 验真加载）。
# - 版本 pin：全局 ARG OPENCODE_MEM_VERSION（见文件头）；bump=改那一行发 PR。
# - 分块清单按 2.41.1 实测划分；c5=剩余物自动兜底；版本变更后若门限红，按 builder 日志 du 重切。
ARG OPENCODE_MEM_VERSION
RUN sed -i "s/__OPENCODE_MEM_VERSION__/${OPENCODE_MEM_VERSION}/" /root/.config/opencode/opencode.json \
 && grep -q "\"opencode-mem@${OPENCODE_MEM_VERSION}\"" /root/.config/opencode/opencode.json \
 && opencode --version
COPY --from=mem-builder /mem/c5/package.json /mem/c5/package-lock.json /root/.cache/opencode/npm/opencode-mem@${OPENCODE_MEM_VERSION}/0/
COPY --from=mem-builder /mem/c5/node_modules /root/.cache/opencode/npm/opencode-mem@${OPENCODE_MEM_VERSION}/0/node_modules
COPY --from=mem-builder /mem/c1/onnxruntime-node /root/.cache/opencode/npm/opencode-mem@${OPENCODE_MEM_VERSION}/0/node_modules/onnxruntime-node
COPY --from=mem-builder /mem/c2/@huggingface /mem/c2/effect /root/.cache/opencode/npm/opencode-mem@${OPENCODE_MEM_VERSION}/0/node_modules/
COPY --from=mem-builder /mem/c3/@opencode /root/.cache/opencode/npm/opencode-mem@${OPENCODE_MEM_VERSION}/0/node_modules/
COPY --from=mem-builder /mem/c4/onnxruntime-web /mem/c4/@img /mem/c4/@opentelemetry /mem/c4/@libsql /mem/c4/@tursodatabase /mem/c4/@redis /mem/c4/@smithy /mem/c4/zod /mem/c4/web-streams-polyfill /mem/c4/@aws-sdk /mem/c4/@opencode-ai /root/.cache/opencode/npm/opencode-mem@${OPENCODE_MEM_VERSION}/0/node_modules/
RUN test -f /root/.cache/opencode/npm/opencode-mem@${OPENCODE_MEM_VERSION}/0/node_modules/opencode-mem/dist/plugin.js \
 && test -d /root/.cache/opencode/npm/opencode-mem@${OPENCODE_MEM_VERSION}/0/node_modules/onnxruntime-node \
 && echo "mem-tree-ok"
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
# CloudRobo 控制面 CLI + Python SDK（具身智能平台；Apache-2.0，PyPI 公开包）：
# - 按需装 9 个控制面子包，不装 hw-cloudrobo-r2c / hw-cloudrobo-ingestion：
#   ingestion 强依赖 r2c[client]（Zenoh/opencv 数据面 ~400M），会把 numpy 2.5.5
#   降到 <2.5、cryptography 50.0.2 降到 <46，重引入 CVE-2026-26007；
#   R2C/回流走边缘侧运行时拉取，不进镜像。
# - 版本 pin：ARG CLOUDROBO_VERSION 单源头；bump=改这行发 PR（goss 断言只认前缀，不两处手抄版本）。
# - crypto 守卫：此层之后 cryptography 主版本必须 >=46（CVE-2026-26007 修在 46.0.5），
#   防新增依赖静默降级（见 2026-11-26 试跑教训）；oci 必须可用（双冒烟）。
ARG CLOUDROBO_VERSION=0.3.0
RUN pip3 install --no-cache-dir --break-system-packages \
      "hw-cloudrobo-core==${CLOUDROBO_VERSION}" \
      "hw-cloudrobo-asset==${CLOUDROBO_VERSION}" \
      "hw-cloudrobo-dataset==${CLOUDROBO_VERSION}" \
      "hw-cloudrobo-train==${CLOUDROBO_VERSION}" \
      "hw-cloudrobo-infer==${CLOUDROBO_VERSION}" \
      "hw-cloudrobo-dispatch==${CLOUDROBO_VERSION}" \
      "hw-cloudrobo-workspace==${CLOUDROBO_VERSION}" \
      "hw-cloudrobo-resource==${CLOUDROBO_VERSION}" \
      "hw-cloudrobo-robot==${CLOUDROBO_VERSION}" \
 && cloudrobo --version \
 && python3 -c "from cloudrobo_core.sdk import Config, HttpClient; Config(); print('cloudrobo-sdk-ok')" \
 && python3 -c "import cryptography; v=cryptography.__version__; assert int(v.split('.')[0])>=46, v; print('crypto-guard-ok', v)" \
 && oci --version
RUN chmod +x /usr/local/bin/send-mail /usr/local/bin/fetch-mail /usr/local/bin/tssh && send-mail --help >/dev/null \
 && fetch-mail --help >/dev/null \
 && tssh --help >/dev/null \
 && echo "tools image ready:" && opencode --version
# 默认直接 serve（compose 仍可用 entrypoint 覆盖；CI 可直接 docker run 起服）
ENTRYPOINT ["opencode"]
CMD ["serve", "--port", "4097", "--hostname", "0.0.0.0"]
