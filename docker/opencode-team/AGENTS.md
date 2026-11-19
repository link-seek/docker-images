# opencode-team 线 · Agent 使用说明（2026-11-19 拆分，独立维护）

本文件**只**描述 `opencode-team`（部门共用精简线）镜像与部署，与 tools 线各自维护、互不照抄。

- **team 线**：opencode + agent-browser（远程 browserless）+ opencode-mem + 邮件 + obsutil + open-design。
- **不含**：aliyun / hcloud / oci / wrangler / tailscale / lmnr / 本地 Chrome。
- tools 线（整套云 CLI + 本地 Chrome）见 `docker/opencode-tools/AGENTS.md`。

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

## 本线可用

- `gh`（已登录；GitHub 代码/PR/Actions 默认走 `gh`，不用 `git` 协议——容器出口抖时 `gh api` 稳）
- url2hc 三条流水线：`download-to-obs.yml` / `img-to-swr.yml` / `build-to-swr.yml`
- `obsutil`（华为云 OBS；`$OBS_ENDPOINT` / `$OBS_AK` / `$OBS_SK` 全走 env）
- `agent-browser` + 远程 browserless（CDP）
- `send-mail` / `fetch-mail`（163 SMTP/IMAP）
- open-design（MCP `open-design-mcp` + skill）
- `opencode-mem`（L2 记忆）

## 本线没有（不要照抄 tools 线的命令）

`hcloud`、`aliyun`、`oci`、`tailscale`、`wrangler`、`lmnr`、本地 Chrome 本线均已砍掉（这些是与 tools 线的差异）。
需要云资源时：查询/上传走 `obsutil` 或 `gh api`；Cloudflare 用 REST + `$CLOUDFLARE_API_TOKEN`；真需要整套云 CLI 就改走 tools 线，别在容器里手工装。
另：`jq` / `yq` / `sops` 两条线都没装——JSON 用 `gh --jq` 或 `python3`，YAML 用 `python3`；sops 解密在流水线/Flux 侧做（本仓 `k8s/**/*.enc.yaml` 由部署链解），不在 agent 容器里跑。

# 密钥验证白名单（只读可直接跑；名单外先问）

- `gh auth status`（GitHub 身份）
- SMTP 建连（`send-mail` 发探针邮件走默认垃圾桶规则；批量群发先确认）
- browserless 健康：`curl -sS "http://browserless.opencode-team.svc.cluster.local:3000/pressure?token=$BROWSERLESS_TOKEN"`（200 即通）
- Cloudflare 只读：`curl -sS -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "https://api.cloudflare.com/client/v4/zones?per_page=5"`
- CF 记忆 key：对 bge-m3 调一次 embedding，1024 维回即通
- 写操作（建 zone / 改 DNS / 删东西 / 发 Worker / 转 tag）除 Cloudflare 授权范围外一律先确认

# 境外源 / 镜像 / 文件（统一走 url2hc 中转）

- 铁律：源在国外的下载/拉取（GitHub release、ghcr.io 镜像、外网文件、pip/npm/go 等境外源）一律优先走 `url2hc` 中转，禁止直连硬扛；直连只在中转失败或不适用时才允许。
- 文件到 OBS：`gh workflow run download-to-obs.yml --repo link-seek/url2hc -f url="<下载地址>" -f obs_key="<文件名>"`，日志里拿 7 天预签名链接（文件 7 天自动删）。
- 镜像到 SWR：`gh workflow run img-to-swr.yml --repo link-seek/url2hc -f source_image="ghcr.io/xxx:tag"`，自动公开 + 7 天老化，拉取地址 `swr.cn-north-4.myhuaweicloud.com/link-seek/<名>:<标签>`（SWR 在 cn-north-4，跨区只能公网拉）。
- Dockerfile 云端构建：`gh workflow run build-to-swr.yml --repo link-seek/url2hc -f target_name="<名>" -f dockerfile_inline="$(cat Dockerfile)"`。
- `gh run watch <id> --exit-status --interval 60`：远端任务跟到底，不 sleep 轮询；默认 60s，急活 30s，底线 15s（防次级限流）。
- 其它 gh 常用：`gh repo list --limit 10`、`gh api` 读文件/调接口、`gh pr`、`gh release`。

# OBS（本线专属）

- 上传/下载一律用 `obsutil`，endpoint/AK/SK 走 `$OBS_ENDPOINT`/`$OBS_AK`/`$OBS_SK`，不落明文。
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
- 地址一律取 `$BROWSER_CDP_URL`（形如 `ws://browserless.opencode-team.svc.cluster.local:3000/chromium?token=...`），**不要写死 `http://browser:9222`**（那是旧 compose 线，已不存在）。
- 健康检查：`curl -sS "http://browserless.opencode-team.svc.cluster.local:3000/pressure?token=$BROWSERLESS_TOKEN"`，HTTP 200 即通；`/json/version` 同样需带 token。
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
- 本线**无本地 headless Chrome**；需要浏览器渲染/`check_open_design_artifact` 时走 `$OPEN_DESIGN_BROWSER_URL`（已指向 browserless）。
- 邮件正文只认 `send-mail -m <.md>`；设计 kit 的 HTML 不许直接 `-f` 发。

# 工作区与卷

- `/workspace` = prod-work（hostPath `/var/lib/opencode-team/work`），git 仓库，改动前会自动 checkpoint。
- `/root/.local/share/opencode` = prod-data（hostPath `/var/lib/opencode-team/data`）；opencode-mem 数据库在此，重建容器不失忆。
- 本线不挂 `/old-workspace`。
- 模型经本地 LiteLLM 网关（`$LITELLM_BASE_URL`）。
- 不要在容器内改 `/root/.config/opencode/` 下文件（随容器重建丢失）；要改就改本镜像仓 `docker/opencode-team/` 后重打镜像。

# 记忆系统

- L1：`/workspace/memory/`（`GLOBAL.md` 个人偏好、`PROJECTS/<名>.md`、`DAILY/` 7 天提炼后删）；做 A 项目只读 A 的文件。
- 目录可能只有骨架（`GLOBAL.md` 不存在时按需新建），不要假装有内容。
- L2：`opencode-mem` 插件（auto-capture + 首条注入）；`memory({mode:"add/search/list/profile/forget"})`；跨项目查显式 `scope:"all-projects"`。
- 记忆正文不进 AGENTS.md。
- 每月 10 分钟晋升评审：稳定的提进 AGENTS.md/L1，错的删。

- 铁律：缺工具禁止容器内手工安装——改 `docker/opencode-team/Dockerfile` 走流水线重打镜像。
