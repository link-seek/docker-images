# opencode-team（部门共用精简线）：opencode + agent-browser + mem + 邮件，其余云 CLI 全砍。
# 用法：docker build --build-arg OPENCODE_TAG=<版本> -f docker/opencode-team/Dockerfile -t <镜像> .
# 与 opencode-tools 的区别：不要 aliyun/hcloud/oci/wrangler/lmnr/tailscale/本地 chrome；
# 浏览器走独立 browserless Pod（部署侧 BROWSER_CDP_URL 指向 browserless Service，agent-browser connect 直连）。
# 背景同 tools：官方 ghcr.io/anomalyco/opencode 镜像是 Alpine/musl，opencode-mem 的
# onnxruntime/turso 原生件缺 fcnt64 起不来（实测）。此文件走 ubuntu:24.04 + 官方 release 二进制。
# 版本 pin：OPENCODE_TAG（dispatch 必填传入）+ opencode-mem（只 Dockerfile 的 ARG 一处定义，构建时注入 jsonc）。
# 注意：CI 全按 dispatch 必填参数构建，从不读这里的默认值；默认值只给本地 docker build 兜底。
# 审计靠 bake run 日志（tag/digest），不在仓里记版本。
ARG OPENCODE_TAG=2.3.0
FROM ubuntu:24.04@sha256:68ee2204a9109b44973313deff7b1de250f1de0f5ecb628d73f579aaff33ac

USER root
SHELL ["/bin/bash", "-c"]

# 安全基线（Trivy 门）：底座 digest 自带 apt 旧版，noble-updates 已有高危修复；
# 定向 --only-upgrade 这两包，不全量 upgrade（减少漂移面）。
RUN apt-get update && apt-get install -y --no-install-recommends --only-upgrade apt libapt-pkg6.0t64 \
 && rm -rf /var/lib/apt/lists/* \
 && apt --version

# 基础运行时（node22 + python/pip + git + ssh + msmtp + gnupg；Ubuntu 自带 node18 不可用，走 NodeSource）。
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git python3 python3-pip openssh-client msmtp gnupg \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list \
    && apt-get update && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
 && git --version && ssh -V && node --version && msmtp --version

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
 && mv "/tmp/gh_${GH_VERSION}_linux_${GH_ARCH}/bin/gh" /usr/local/bin/gh \
 && rm -rf /tmp/gh.tar.gz "/tmp/gh_${GH_VERSION}_linux_${GH_ARCH}" \
 && gh --version

# agent-browser：npm（远程 browserless 走 CDP，不在本镜像内装浏览器）
RUN npm install -g "agent-browser@${AGENT_BROWSER_VERSION}" \
 && agent-browser --version \
 && npm cache clean --force && rm -rf /root/.npm

# 设计能力（feimacode/open-design-agent-kit，社区包；skill 走官方 skills.sh 装最新版，不 pin——浮动跟随，出问题再定）：
# - skill 文件：build 期 `skills add -a opencode -g` 装到 opencode 认的全局目录（~/.agents/skills）。
# - MCP server：不烘焙，opencode.json 里用 npx 随调随下（首启慢一次，之后走缓存）。
# - 版本审计靠镜像 digest（构建时 main 快照）；想锁死再切回 npm pin 方案。
RUN npx -y skills add https://github.com/feimacode/open-design-agent-kit --skill open-design -a opencode -g --yes \
 && test -f /root/.agents/skills/open-design/SKILL.md

# 非涉密默认配置烘入镜像（各机器行为一致；密钥仍走 env/挂载，不进镜像）：
# - opencode.jsonc：模型走 LiteLLM 网关 + plugins pin 死 opencode-mem
# - opencode-mem.jsonc：记忆插件配置（storagePath 钉 prod-data 卷，密钥全走 env://）
# - AGENTS.md：agent 使用说明（含记忆系统规约）
# 注意：部署侧不要再挂载这些文件，否则会盖住烘入的版本。
# 注意：源文件叫 opencode.jsonc（保留注释），但必须落盘为 opencode.json——
# 2.1.4 实测 daemon 只读 opencode.json，.jsonc 同内容零命中（debug config 0 结果）。
COPY docker/opencode-team/opencode-mem.jsonc docker/opencode-team/AGENTS.md /root/.config/opencode/
COPY docker/opencode-team/opencode.jsonc /root/.config/opencode/opencode.json
# opencode-mem 插件本体烘入（约 600MB natives；构建机一次下载，运行免下）。
# 单源头落位：ARG 是唯一版本号来源——先把 jsonc 占位符注入成实值（注入失败直接红），再按同一值 install。
ARG OPENCODE_MEM_VERSION=2.41.1
RUN sed -i "s/__OPENCODE_MEM_VERSION__/${OPENCODE_MEM_VERSION}/" /root/.config/opencode/opencode.json \
 && grep -q "\"opencode-mem@${OPENCODE_MEM_VERSION}\"" /root/.config/opencode/opencode.json \
 && opencode plugin add "opencode-mem@${OPENCODE_MEM_VERSION}"
# - send-mail：msmtp 薄包装（配置全走 SMTP_* 环境变量）
# - fetch-mail：IMAP 只读薄客户端（标准库 imaplib；IMAP_* 缺省回落 SMTP_*，163 收发共用授权码）
# - md2html：send-mail -m 用的 markdown→HTML 转换（烘焙 markdown+premailer）
COPY docker/opencode-team/send-mail.sh /usr/local/bin/send-mail
COPY docker/opencode-team/fetch-mail.py /usr/local/bin/fetch-mail
COPY docker/opencode-team/md2html.py /usr/local/lib/send-mail/md2html.py
ARG MD_DEPS="markdown==3.7 premailer==3.10.0"
RUN pip3 install --no-cache-dir --break-system-packages $MD_DEPS \
 && python3 -c "import markdown, premailer; print('md-ok')"
RUN chmod +x /usr/local/bin/send-mail /usr/local/bin/fetch-mail && send-mail --help >/dev/null \
 && fetch-mail --help >/dev/null \
 && echo "team image ready:" && opencode --version
# 默认直接 serve（部署侧 entrypoint 覆盖；CI 可直接 docker run 起服）
ENTRYPOINT ["opencode"]
CMD ["serve", "--port", "4097", "--hostname", "0.0.0.0"]
