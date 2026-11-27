# opencode-team（部门共用精简线）：opencode + agent-browser + mem + 邮件 + obsutil；其余云 CLI 全砍。
# 用法：docker build --build-arg OPENCODE_TAG=<版本> -f docker/opencode-team/Dockerfile -t <镜像> .
# 与 opencode-tools 的区别：不要 aliyun/hcloud/oci/wrangler/lmnr/tailscale/本地 chrome；
# 浏览器走独立 browserless Pod（部署侧 BROWSER_CDP_URL 指向 browserless Service，agent-browser connect 直连）。
# 背景同 tools：官方 ghcr.io/anomalyco/opencode 镜像是 Alpine/musl，opencode-mem 的
# onnxruntime/turso 原生件缺 fcnt64 起不来（实测）。此文件走 ubuntu:24.04 + 官方 release 二进制。
# 版本 pin：OPENCODE_TAG（dispatch 必填传入）+ opencode-mem（只 Dockerfile 的 ARG 一处定义，构建时注入 jsonc）。
# 注意：CI 全按 dispatch 必填参数构建，从不读这里的默认值；默认值只给本地 docker build 兜底。
# 审计靠 bake run 日志（tag/digest），不在仓里记版本。
ARG OPENCODE_TAG=2.4.2

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

FROM ubuntu:24.04@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac

USER root
SHELL ["/bin/bash", "-c"]

# 安全基线（Trivy 门）：底座 digest 自带 apt 旧版，noble-updates 已有高危修复；
# 定向 --only-upgrade 这两包，不全量 upgrade（减少漂移面）。
RUN apt-get update && apt-get install -y --no-install-recommends --only-upgrade apt libapt-pkg6.0t64 \
 && rm -rf /var/lib/apt/lists/* \
 && apt --version

# 基础运行时（node22 + python/pip + git + ssh(+sshpass) + msmtp + gnupg；Ubuntu 自带 node18 不可用，走 NodeSource）。
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

# opencode 官方二进制（glibc 版；x64 取 baseline，最大 CPU 兼容；arm64 无 baseline 变体）
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

# 版本 pin（沿用 tools 验证过的版本）
ARG GH_VERSION=2.103.3
ARG AGENT_BROWSER_VERSION=0.41.0

# gh：官方 tarball（Go 静态二进制）
RUN ARCH="$(uname -m)"; case "$ARCH" in x86_64) GH_ARCH=amd64;; aarch64) GH_ARCH=arm64;; *) echo "unsupported arch $ARCH" && exit 1;; esac \
 && curl -fsSL -o /tmp/gh.tar.gz \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz" \
 && tar -xzf /tmp/gh.tar.gz -C /tmp \
 && mkdir -p /usr/local/libexec \
 && mv "/tmp/gh_${GH_VERSION}_linux_${GH_ARCH}/bin/gh" /usr/local/libexec/gh-real \
 && chmod +x /usr/local/libexec/gh-real \
 && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_${GH_ARCH}" \
 && /usr/local/libexec/gh-real --version

# gh 命令级护栏（team 线）：/usr/local/bin/gh 是 wrapper，只放行 `gh issue create`；
# 真二进制移到 /usr/local/libexec/gh-real。注意这是防误用护栏，不是安全边界（token 未降权）。
COPY docker/opencode-team/gh-restrict.sh /usr/local/bin/gh
RUN chmod +x /usr/local/bin/gh \
 && gh --version \
 && gh issue create --help >/dev/null \
 && if gh api /user >/dev/null 2>&1; then echo "FAIL: gh-restrict 未生效（gh api 应被拒）" >&2; exit 1; fi \
 && echo "gh-restrict ok: 仅 issue create"

# obsutil（华为云 OBS 官方 CLI，单二进制；agent 直调做上传/下载；endpoint/ak/sk 全走 env，密钥不进镜像）。
# 下载站为华为云内网域名（国内直连）；该桶仅 current 路径公开，pin 策略=URL 取 current + 构建期断言版本号漂移即红。
ARG OBSUTIL_EXPECT_VERSION=5.8.9
# /current/ 无版本化路径；对 amd64 钉 sha256，上游漂移即构建失败（fail-closed，显式 bump）。
ARG OBSUTIL_SHA256_AMD64=1f9111dde3fd9e894978b3281159d385f13bfd24beaad34a9bfb959f10013905
RUN ARCH="$(uname -m)"; case "$ARCH" in x86_64) OBS_ARCH=amd64;; aarch64) OBS_ARCH=arm64;; *) echo "unsupported arch $ARCH" && exit 1;; esac \
 && curl -fsSL -o /tmp/obsutil.tar.gz \
      "https://obs-community.obs.cn-north-1.myhuaweicloud.com/obsutil/current/obsutil_linux_${OBS_ARCH}.tar.gz" \
 && if [ "$OBS_ARCH" = "amd64" ]; then echo "${OBSUTIL_SHA256_AMD64}  /tmp/obsutil.tar.gz" | sha256sum -c -; fi \
 && tar -xzf /tmp/obsutil.tar.gz -C /tmp \
 && mv /tmp/obsutil_linux_${OBS_ARCH}_*/obsutil /usr/local/bin/obsutil \
 && chmod +x /usr/local/bin/obsutil && rm -rf /tmp/obsutil.tar.gz /tmp/obsutil_linux_${OBS_ARCH}_* \
 && obsutil help >/dev/null && echo "obsutil ok (expect ${OBSUTIL_EXPECT_VERSION})"

# agent-browser：npm（远程 browserless 走 CDP，不在本镜像内装浏览器）
RUN npm install -g "agent-browser@${AGENT_BROWSER_VERSION}" \
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

# 非涉密默认配置烘入镜像（各机器行为一致；密钥仍走 env/挂载，不进镜像）：
# - opencode.jsonc：模型走 LiteLLM 网关 + plugins pin 死 opencode-mem
# - opencode-mem.jsonc：记忆插件配置（storagePath 钉 prod-data 卷，密钥全走 env://）
# - AGENTS.md：agent 使用说明（含记忆系统规约）
# 注意：部署侧不要再挂载这些文件，否则会盖住烘入的版本。
# 注意：源文件叫 opencode.jsonc（保留注释），但必须落盘为 opencode.json——
# 2.1.4 实测 daemon 只读 opencode.json，.jsonc 同内容零命中（debug config 0 结果）。
COPY docker/_shared/opencode-mem.jsonc /root/.config/opencode/
COPY docker/opencode-team/AGENTS.md /root/.config/opencode/
COPY docker/opencode-team/opencode.jsonc /root/.config/opencode/opencode.json
# opencode-mem 插件本体烘入（约 600MB natives；构建机一次下载，运行免下）。
# 单源头落位：ARG 是唯一版本号来源——先把 jsonc 占位符注入成实值（注入失败直接红），再按同一值 install。
ARG OPENCODE_MEM_VERSION=2.41.1
RUN sed -i "s/__OPENCODE_MEM_VERSION__/${OPENCODE_MEM_VERSION}/" /root/.config/opencode/opencode.json \
 && grep -q "\"opencode-mem@${OPENCODE_MEM_VERSION}\"" /root/.config/opencode/opencode.json \
 && opencode plugin add "opencode-mem@${OPENCODE_MEM_VERSION}" \
 && npm cache clean --force && rm -rf /root/.npm /tmp/* ~/.cache
# opencode-cognee 文件插件（与 tools 线同版本；OpenCode 目录扫描加载，不写 jsonc plugins 数组）。
# 迁移期与 opencode-mem 共存：mem 只读旧库做迁移源，线上读写走 cognee；迁移验证后另起 PR 下掉 mem。
ARG OPENCODE_COGNEE_VERSION=0.5.0
RUN curl -fsSL -o /tmp/cognee.tgz \
      "https://github.com/link-seek/opencode-cognee/archive/refs/tags/v${OPENCODE_COGNEE_VERSION}.tar.gz" \
 && tar -xzf /tmp/cognee.tgz -C /tmp \
 && mkdir -p /.opencode/plugins/cognee \
 && cp "/tmp/opencode-cognee-${OPENCODE_COGNEE_VERSION}/.opencode/plugins/cognee/index.ts" "/tmp/opencode-cognee-${OPENCODE_COGNEE_VERSION}/.opencode/plugins/cognee/lib.ts" /.opencode/plugins/cognee/ \
 && grep -q 'id: "cognee"' /.opencode/plugins/cognee/index.ts \
 && grep -q 'safeDatasetName' /.opencode/plugins/cognee/lib.ts \
 && rm -rf /tmp/cognee.tgz "/tmp/opencode-cognee-${OPENCODE_COGNEE_VERSION}" \
 && npm cache clean --force && rm -rf /root/.npm /tmp/opencode-* 2>/dev/null; opencode --version
# - send-mail：msmtp 薄包装（配置全走 SMTP_* 环境变量）
# - fetch-mail：IMAP 只读薄客户端（标准库 imaplib；IMAP_* 缺省回落 SMTP_*，163 收发共用授权码）
# - md2html：send-mail -m 用的 markdown→HTML 转换（烘焙 markdown+premailer）
COPY docker/_shared/send-mail.sh /usr/local/bin/send-mail
COPY docker/_shared/fetch-mail.py /usr/local/bin/fetch-mail
COPY docker/_shared/md2html.py /usr/local/lib/send-mail/md2html.py
ARG MD_DEPS="markdown==3.7 premailer==3.10.0"
RUN pip3 install --no-cache-dir --break-system-packages $MD_DEPS \
 && python3 -c "import markdown, premailer; print('md-ok')"
RUN chmod +x /usr/local/bin/send-mail /usr/local/bin/fetch-mail && send-mail --help >/dev/null \
 && fetch-mail --help >/dev/null \
 && echo "team image ready:" && opencode --version
# 默认直接 serve（部署侧 entrypoint 覆盖；CI 可直接 docker run 起服）
ENTRYPOINT ["opencode"]
CMD ["serve", "--port", "4097", "--hostname", "0.0.0.0"]
