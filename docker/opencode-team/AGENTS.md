# opencode-team 线 · Agent 使用说明（2026-11-19 拆分，独立维护）

本文件**只**描述 `opencode-team`（部门共用精简线）镜像与部署，与 tools 线各自维护、互不照抄。

- **team 线**：opencode + agent-browser（远程 browserless）+ cognee（长期记忆）+ 邮件 + obsutil + open-design。
- **不含**：aliyun / hcloud / oci / wrangler / tailscale / lmnr / 本地 Chrome。
- tools 线（整套云 CLI）见 `docker/opencode-tools/AGENTS.md`；浏览器两条线都一样走独立 browserless，镜像内无本地 Chrome。

# 打包 vs 部署分工铁律（2026-11-16 修订，与 infra#461/#490 同源）

- **商家（本仓及各应用仓）对运行结果负责**：业务逻辑 + 镜像 + manifest + 配送闭环，digest 即行为版本号；manifest 跟镜像走，同一仓同一 PR。
- **infra 只留底座**：flux-system、egress、etcd、Caddy/DNS、tailnet、namespace/配额/网络策略；pod 层（manifest/env/secret/副本/pin）一律是应用仓的事，infra 不伸手。
- **配送 = Flux pull**：生产 Flux 对账 main 分支 manifest 自动拉；老 compose `deliver-*` 已退役（k3s-apply 仅留 Secret 轮换应急）。
- **回滚 = 换 digest/revert**：git 历史即备份，不在机器上存回滚逻辑。
- **密钥**：真值只活 GitHub Secrets + 目标机 `.env`（600）/ K8s Secret；镜像内无真值（`LITELLM_*` 等全走 env 引用）。

# 生产环境与本线边界

本容器的凭证（GH / Cloudflare / OBS / LiteLLM / MAAS / SMTP）已由部署注入 env，**不要向用户索取任何密钥**。所有查询优先只读；变更类操作先向用户确认。

- 铁律：测试/验证类负载只跑 GitHub 临时 runner（ephemeral，现建现焚），禁止落到生产常驻节点（hw21/hw41/ali-gz/.69 k3s 等）——含 canary、探针、试送靶机。生产只接受 Flux 对账/main 切流。
- 触发分级：`user` 身份（只动 HW）可流水线触发、无人值守——门禁全绿＋fail-closed，只验收结果；`admin` 身份（碰 OCI/阿里云等非 HW）必须活人手动 dispatch、全程盯到底，禁止自动触发。
- 底座红线（软约束，RBAC/Kyverno/分支保护是硬底；下面每一次越线都必须单独向用户确认）：
  越线清单：直推 main、`--admin` 合并、写 flux-system/kube-system/kube-public/kube-node-lease/kyverno、删改线上数据、云 AK 高危操作（开关机/删机/改网络/删资源）、节点 SSH 写操作、用 `GH_TOKEN` 合并 main。
  协议：识别出越线 → 立刻停下 → 用显式提问逐项确认，每次越线单独确认一次，不把多次越线打包成一次确认，不默认通过；被拒（RBAC/Kyverno/分支保护）就停，不要绕行。
  正常链路：发布走代码仓+Flux+digest pin，手动 kubectl 只限 `opencode-sandbox`/自有 ns 试飞；云凭证与节点 SSH 默认只读；`GH_TOKEN` 只用于开 PR/推分支。

## 本线可用

- `gh`（已登录；**经 wrapper 限制：仅 `gh issue create`**，其余命令被拒——见「GitHub（gh 受限）」）
- url2hc 三条流水线：`download-to-obs.yml` / `img-to-swr.yml` / `build-to-swr.yml`
- `obsutil`（华为云 OBS；`$OBS_ENDPOINT` / `$OBS_AK` / `$OBS_SK` 全走 env）
- `agent-browser` + 远程 browserless（CDP）
- `send-mail` / `fetch-mail`（163 SMTP/IMAP）
- open-design（MCP `open-design-mcp` + skill）
- `cognee` 文件插件（长期记忆：`memory_search` / `memory_remember` 工具 + 自动召回/归档；身份固定为 `team`）
- `ssh` / `sshpass`（openssh-client + 密码认证）：免密走 key/agent；只有密码时用 `SSHPASS="$PW" sshpass -e ssh -o StrictHostKeyChecking=accept-new user@host '<cmd>'`（`-p` 会把密码带进 ps，别用）。本线不在 tailnet，目标机走可达 IP/域名；私钥/密码不进镜像。

## 本线没有（不要照抄 tools 线的命令）

`hcloud`、`aliyun`、`oci`、`tailscale`、`wrangler`、`lmnr`、本地 Chrome 本线均已砍掉（这些是与 tools 线的差异）。
注意：无 `hcloud` 只表示没有 KooCLI 命令；**华为云 OBS 的 AK/SK（`$OBS_AK`/`$OBS_SK`）与 `$OBS_ENDPOINT` 必须保留**，obsutil 依赖它们，别当无用凭证删掉。
需要云资源时：查询/上传走 `obsutil`；Cloudflare 用 REST + `$CLOUDFLARE_API_TOKEN`；真需要整套云 CLI 就改走 tools 线，别在容器里手工装。

# 密钥验证白名单（只读可直接跑；名单外先问）

- `gh auth status`（GitHub 身份）
- SMTP 建连（`send-mail` 发探针邮件走默认垃圾桶规则；批量群发先确认）
- browserless 健康：`curl -sS "http://browserless.opencode-team.svc.cluster.local:3000/pressure"`（200 即通；本线 browserless 无 token，仅集群内可达）
- Cloudflare 只读：`curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/zones?per_page=5"`
- CF 记忆 key：对 bge-m3 调一次 embedding，1024 维回即通
- 写操作（建 zone / 改 DNS / 删东西 / 发 Worker / 转 tag）除 Cloudflare 授权范围外一律先确认

# 境外源 / 镜像 / 文件（统一走 url2hc 中转）

- 铁律：源在国外的下载/拉取（GitHub release、ghcr.io 镜像、外网文件、pip/npm/go 等境外源）一律优先走 `url2hc` 中转，禁止直连硬扛；直连只在中转失败或不适用时才允许。
- ⚠️ 本容器 `gh` 被限制为仅 `gh issue create`，**不能直接触发 workflow**。以下命令供有 gh 权限的环境（CI / 人工 / 宿主机）执行，pod 内仅作参考：
  - 文件到 OBS：`gh workflow run download-to-obs.yml --repo link-seek/url2hc -f url="<下载地址>" -f obs_key="<文件名>"`，日志里拿 7 天预签名链接（文件 7 天自动删）。
  - 镜像到 SWR：`gh workflow run img-to-swr.yml --repo link-seek/url2hc -f source_image="ghcr.io/xxx:tag"`，自动公开 + 7 天老化，拉取地址 `swr.cn-north-4.myhuaweicloud.com/link-seek/<名>:<标签>`（SWR 在 cn-north-4，跨区只能公网拉）。
  - Dockerfile 云端构建：`gh workflow run build-to-swr.yml --repo link-seek/url2hc -f target_name="<名>" -f dockerfile_inline="$(cat Dockerfile)"`。
  - 跟进度：`gh run watch <id> --exit-status --interval 60`（默认 60s，急活 30s，底线 15s）。
- 需要触发上述流水线时：请提示用户/CI 侧执行，或让有权限的机器人处理；不要试图绕过 gh 限制。

# GitHub（gh 受限）

- 本容器 `gh` 是 wrapper（真二进制 `/usr/local/libexec/gh-real`）：**仅放行 `gh issue create`**，另放行 `--help` / `--version` / `version` / `auth status`。
- 被拒：`gh api`、`gh pr`、`gh workflow`、`gh repo`、`gh release` 及其它子命令。
- 提 issue：`gh issue create -R link-seek/<repo> -t "标题" -b "正文"`。
- ⚠️ 这是**防误用护栏，不是安全边界**：token 仍为全权限，直接调 `gh-real` 或自行用 `$GH_TOKEN` 发 HTTP 可绕过；不要把它当隔离手段宣传。

# OBS（本线专属）

- 上传/下载一律用 `obsutil`，endpoint/AK/SK 走 `$OBS_ENDPOINT`/`$OBS_AK`/`$OBS_SK`，不落明文。
- **华为云 AK/SK 必须保留**：`$OBS_AK`/`$OBS_SK`/`$OBS_ENDPOINT` 由 deployment 注入，是 obsutil 的凭据；砍的只是 `hcloud` 命令层，不是华为云凭证。缺凭证按报错补 Secret，不向用户索取。
- 例：`obsutil ls obs://<bucket>/`、`obsutil cp <本地文件> obs://<bucket>/<key>`、`obsutil sign obs://<bucket>/<key>`（临时预签名）。
- 预签名有效期按需给，别生成长期公开链接。

# Cloudflare（本线无 wrangler，用 REST + token）

- token 走 `$CLOUDFLARE_API_TOKEN`（部署时 mint，过期报错先确认有效期）。
- 查 zone：`curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/zones?per_page=50"`
- 查 DNS：`curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/zones/<zone_id>/dns_records?name=<fqdn>"`
- 改 DNS：`curl -sS -X PATCH -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" -H "Content-Type: application/json" "https://api.cloudflare.com/client/v4/zones/<zone_id>/dns_records/<id>" --data '{...}'`
- 红线：切 NS（注册商侧）、删 zone/记录等影响现网步骤，执行前必须先向用户确认；只动授权范围内的域。

# 浏览器自动化（远程 browserless 独立 Pod）

- 浏览器**不在本镜像内，也不在同 Pod**；是 `opencode-team` namespace 里独立的 `browserless` Deployment（Service 端口 3000）。
- 地址一律取 `$BROWSER_CDP_URL`（形如 `ws://browserless.opencode-team.svc.cluster.local:3000/chromium`，本线无 token），**不要写死 `http://browser:9222`**（那是旧 compose 线，已不存在）。
- 健康检查：`curl -sS "http://browserless.opencode-team.svc.cluster.local:3000/pressure"`，HTTP 200 即通；`/json/version` 直接可读（无需 token）。
- 动手前先拉配套用法：`agent-browser skills get core`（不要靠记忆拼命令）。
- 典型流程：`agent-browser --cdp "$BROWSER_CDP_URL" open <url>` → `snapshot -i` → `click @e2` / `fill @e3 "文本"` → `screenshot` → `close`。
- 每次调用必须带 `--cdp "$BROWSER_CDP_URL"`。
- 单会话上限 10 分钟（browserless `TIMEOUT=600000`）；长任务分段，或保证提前 `close` 释放。
- 禁止在本容器内执行 `agent-browser install`（Chrome 由 browserless Pod 提供）。

# 邮件通知 / 读取

- `send-mail <收件人> <主题> <正文>`；收件人多个用逗号或空格分隔。
- 正文长时：`echo "..." | send-mail <收件人> <主题>`，或 `send-mail <收件人> <主题> -f <文件>`，或 `-m <.md>`（markdown→HTML 富文本）。
- 缺省收件人取环境变量 `$MAIL_DEFAULT_TO`（部署侧设定，勿在文档写死）；收件人传空字符串即走默认，如 `send-mail "" "主题" "正文"`。
- 长任务完成/失败后主动发一封告知结果；定时巡检输出摘要后发。
- `fetch-mail list --limit 10` / `unread` / `show <uid>`：只读 EXAMINE，不改已读、不删信；`IMAP_*` 缺省回落 `SMTP_*`（163 收发共用授权码）；被问到才看，不轮询。
- 发前确认收件人；缺配置按报错补 `.env`/Secret 后重载，不索取密码。

# 设计能力

- 走 MCP `open-design` 工具（`list_open_design_skills` → `prepare_open_design_brief`，绑 `DESIGN.md` 再写 HTML），产物落 `/workspace`。
- 本线**无本地 headless Chrome**；需要浏览器渲染/`check_open_design_artifact` 时走 `$OPEN_DESIGN_BROWSER_URL`（`http://browserless.opencode-team.svc.cluster.local:3000`，kit 经 puppeteer.connect 远程渲染）。
- 邮件正文只认 `send-mail -m <.md>`；设计 kit 的 HTML 不许直接 `-f` 发。

# 工作区与卷

- `/workspace` = prod-work（hostPath `/var/lib/opencode-team/work`），git 仓库，改动前会自动 checkpoint。
- `/root/.local/share/opencode` = prod-data（hostPath `/var/lib/opencode-team/data`）；旧 opencode-mem 库已归档为 `opencode-mem.retired-*`（只读备份），线上记忆走 Cognee（`u_team`）。
- 本线不挂 `/old-workspace`。
- 模型经本地 LiteLLM 网关（`$LITELLM_BASE_URL`）。
- 不要在容器内改 `/root/.config/opencode/` 下文件（随容器重建丢失）；要改就改本镜像仓 `docker/opencode-team/` 后重打镜像。

# 记忆系统

- L1：`/workspace/memory/`（`GLOBAL.md` 个人偏好、`PROJECTS/<名>.md`、`DAILY/` 7 天提炼后删）；做 A 项目只读 A 的文件。
- 目录可能只有骨架（`GLOBAL.md` 不存在时按需新建），不要假装有内容。
- L2：`cognee` 插件（按 `team` 身份自动召回/闲时归档）；显式读写用 `cognee` 命名空间下的 `memory_search` / `memory_remember` 工具。
- 记忆正文不进 AGENTS.md。
- 每月 10 分钟晋升评审：稳定的提进 AGENTS.md/L1，错的删。

- 铁律：缺工具禁止容器内手工安装——改 `docker/opencode-team/Dockerfile` 走流水线重打镜像。
