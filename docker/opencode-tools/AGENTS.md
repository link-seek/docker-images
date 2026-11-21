# 打包 vs 部署分工铁律（2026-11-16 修订，与 infra#461/#490 同源）

- **商家（本仓及各应用仓）对运行结果负责**：业务逻辑 + 镜像 + manifest + 配送闭环，digest 即行为版本号；manifest 跟镜像走，同一仓同一 PR。
- **infra 只留底座**：flux-system、egress、etcd、Caddy/DNS、tailnet、namespace/配额/网络策略；pod 层（manifest/env/secret/副本/pin）一律是应用仓的事，infra 不伸手。
- **配送 = Flux pull**：生产 Flux 对账 main 分支 manifest 自动拉；老 compose `deliver-*` 已退役（k3s-apply 仅留 Secret 轮换应急）。
- **回滚 = 换 digest/revert**：git 历史即备份，不在机器上存回滚逻辑。
- **密钥**：真值只活 GitHub Secrets + 目标机 `.env`（600）；本镜像内无真值（`LITELLM_*` 等全走 env 引用）。

# 生产环境说明（直连模型）

本容器内各云 CLI 已直接配好凭证。需要查云资源时直接在容器内执行对应 CLI。不要向用户索取任何密钥。所有查询优先只读。执行变更类操作前必须先向用户确认。

- 铁律：所有测试/验证类负载只跑在 GitHub 临时 runner（ephemeral，现建现焚）上；禁止以任何形式落到生产常驻节点（hw21/hw41/ali-gz/.69 k3s 等）——含 canary、探针、试送靶机、tailnet 加网生产簇。生产只接受 Flux 对账/main 切流；k3d 预检等验证一律用 ephemeral runner + 临时名。（2026-11-02 hw41 误投教训：deliver-stack 曾被 dispatch 到 host:mesh-hw-41 起 canary，探针红才没切流；此后生产节点只跑正式切流，不当试验场。）
- 触发分级：`user` 身份（只动 HW）可流水线触发、无人值守——门禁全绿＋fail-closed，只验收结果；`admin` 身份（碰 OCI/阿里云等非 HW）必须活人手动 dispatch、全程盯到底，禁止自动触发。

密钥验证白名单（只读验证可直接跑，不用问；名单外的命令先问）：
- `gh auth status`（GitHub 身份）
- `hcloud ECS ListServersDetails --limit 1 --cli-region=cn-north-4`（华为云连通）
- `wrangler whoami`（Cloudflare 身份）
- SMTP 建连（`send-mail` 发探针邮件走默认垃圾桶规则；批量群发先确认）
- `tailscale status`（本节点在线）
- CF 记忆 key：调一次 bge-m3 embedding（1024 维回即通）
- 写操作（建 zone/改 DNS/删东西/发 Worker/转 tag）除 Cloudflare 授权范围外一律先确认。

可用工具：

- 铁律：所有源在国外的下载/拉取（GitHub release、ghcr.io 镜像、外网文件、pip/npm/go 等境外源），一律优先走 `url2hc` 中转，禁止直连硬扛。直连只有当中转失败或不适用时才允许。
- 文件到 OBS：`gh workflow run download-to-obs.yml --repo link-seek/url2hc -f url="<下载地址>" -f obs_key="<文件名>"`，日志里拿 7 天预签名链接（文件 7 天自动删）。
- 镜像到 SWR：`gh workflow run img-to-swr.yml --repo link-seek/url2hc -f source_image="ghcr.io/xxx:tag"`，自动公开 + 7 天老化，拉取地址 `swr.cn-north-4.myhuaweicloud.com/link-seek/<名>:<标签>`（SWR 在 cn-north-4，跨区只能公网拉）。
- Dockerfile 云端构建：`gh workflow run build-to-swr.yml --repo link-seek/url2hc -f target_name="<名>" -f dockerfile_inline="$(cat Dockerfile)"`。
- `gh repo list --limit 10`：查看 GitHub 仓库
- `gh repo clone OWNER/REPO`：GitHub 克隆默认走 gh（已含 `gh auth` 身份），不用 `git clone`
- GitHub 代码操作默认优先 gh（`gh api` 读文件/调接口、`gh pr`、`gh run`、`gh release`）；git 协议只作 fallback（容器出口抖时 `gh api` 常比 github.com 稳）。
- `gh run watch <id> --exit-status --interval 60`：远端任务跟到底，不用 sleep 轮询；默认 60s，急活 30s，底线 15s（防次级限流）。
- `hcloud ECS ListServersDetails --limit 5 --cli-region=cn-north-4`：华为云华北四区 ECS
- `aliyun ecs DescribeInstances --RegionId cn-hangzhou`：阿里云杭州地域实例
- `oci compute instance list --compartment-id <ocid> --all`：甲骨文云实例
- `tailscale status`：查看 tailnet 节点状态

Cloudflare 自助（`wrangler` 已烘入镜像，token 走 `.env` 的 `CLOUDFLARE_API_TOKEN`，每次发版现签 90 天读写）：
owner 已授权你直接操作，用于 DNS 调整、yingxin 迁移、Workers/Pages 等任务。
- 查：`wrangler zones list` / `wrangler dns list <zone>`（只读先行）。
- 改：建 zone、改 DNS、发 Worker 都可以直接做；DNS/Zone/Workers/Pages 读写全开（账号 zone 通配）。
- 红线：切 NS（注册商侧）、删 zone/记录等影响现网的步骤，执行前必须先向用户确认；只动授权范围内的域。
- token 90 天过期，发版自动续；过期报错先看 token 有效期，不要怀疑人生。

浏览器自动化（`agent-browser` CLI 已烘入镜像 + 独立 `browser` sidecar，经 CDP 连接；浏览器不在本镜像内）：

- 每次调用必须带 `--cdp "$BROWSER_CDP_URL"`（默认 `http://browser:9222`，compose 服务名即地址）。
- 动手前先拉与安装版本配套的用法：`agent-browser skills get core`（不要靠记忆拼命令）。
- 典型流程：`agent-browser --cdp "$BROWSER_CDP_URL" open <url>` → `snapshot -i` → `click @e2` / `fill @e3 "文本"` → `screenshot` → `close`。
- 先确认浏览器在线：`curl -s http://browser:9222/json/version`。
- 禁止在本容器内运行 `agent-browser install`（Chrome 由 browser sidecar 提供，不要装进 tools 镜像）。

邮件通知（`send-mail` + msmtp 已烘入镜像，SMTP 配置走 `.env` 的 `SMTP_*`，密钥不进镜像）：

- `send-mail <收件人> <主题> <正文>`：收件人多个用逗号分隔，如 `send-mail "a@x.com,b@x.com" "主题" "正文"`。
- 正文长时：`echo "..." | send-mail <收件人> <主题>` 或 `send-mail <收件人> <主题> -f <文件>`。
- 用户说“发邮件给我/他”时直接用此命令；长任务完成或失败后主动发一封告知结果；定时巡检（宿主机 cron/systemd 调 `opencode run`）输出摘要后发。
- 用户的默认邮箱是 122306789@qq.com：用户说“发给我”又没给地址时直接发这里，不用再问；`MAIL_DEFAULT_TO` 已配好，收件人传空字符串即走默认，如 `send-mail "" "主题" "正文"`。
- 发前确认收件人正确；缺配置时按报错补 `.env` 后重启容器生效，不要向用户索取密码。

SSH 直连（`tssh` 已烘入镜像，key-only，免 pty 喂密码）：

- `tssh [-i key] [-p port] <host> -- <cmd>`：key 路径 `-i` > `$TSSH_KEY` > `~/.ssh/id_hw21`（容器外挂载，私钥不进镜像）；端口 `-p` > `$TSSH_PORT` > 22。
- 固定 `BatchMode + PasswordAuthentication=no + StrictHostKeyChecking=accept-new + ConnectTimeout`（默认 10，`TSSH_CONNECT_TIMEOUT` 可调）；无 key 直接报错，不回落密码。
- 只验包装不断言真连：`tssh --dry-run <host> -- <cmd>` 打印最终 ssh 命令行（goss/e2e 靠它断言）。

邮件读取（`fetch-mail` + 标准库 imaplib 只读，已烘入镜像；`IMAP_*` 缺省回落 `SMTP_*`，163 收发共用同一授权码）：

- 163 配置：`IMAP_HOST=imap.163.com`，`IMAP_PORT=993 SSL`；`IMAP_USER/IMAP_PASS` 不配则自动用 `SMTP_USER/SMTP_PASS`。
- 按需查看（只读 EXAMINE，不改已读、不删信）：`fetch-mail list --limit 10` / `fetch-mail unread --limit 10` / `fetch-mail show <uid>`。
- AI 被问到才看，不轮询、不常驻；缺配置时按报错补 `.env` 后重启容器生效。

设计能力（`open-design` skill + MCP，已烘入镜像；文件全落 `/workspace`，无 daemon/网页/写回）：

- 设计需求先走 MCP `open-design` 工具（`list_open_design_skills` → `prepare_open_design_brief`，绑 `DESIGN.md` 再写 HTML），模型走网关，产物即文件。
- 邮件正文只认 `send-mail -m <.md>`，设计 kit 的 HTML 不许直接 `-f` 发（收件端兼容两条链，见 Dockerfile 注释）。
- 要机器验（横滚/对比度/焦点）跑 `check_open_design_artifact`（本地 headless 浏览器已烘入）；`export email` 未启用前，营销邮件仍人眼终验。

工作区说明：

- `/workspace` 为默认工作目录（git 仓库，改动前会自动 checkpoint）。
- 若挂载了 `/old-workspace`，那是历史业务目录，优先只读；需要改动必须先向用户确认。
- 模型经由本地 LiteLLM 网关调用。不要在容器内改动 `/root/.config/opencode/` 下的文件（随容器重建丢失）；要改默认配置请改镜像仓库重打镜像。

- 铁律：运行环境缺工具时，禁止在容器内手工安装——去仓库 Dockerfile 加、走流水线重打镜像（2026-10-09 runner 黑户事故教训，详见 docker/README.md）。

记忆系统（L1 文件 + L2 向量，设计见仓库 Discussions #11）：

- L1：规矩在各 AGENTS.md；内容在 `/workspace/memory/`（`GLOBAL.md` 个人偏好、`PROJECTS/<名>.md` 项目架构决策踩坑、`DAILY/` 临时沉淀）。做 A 项目只读 A 的文件，不相关的不进上下文。
- 开工读 `GLOBAL.md` + 对应 `PROJECTS` 文件（`memory({mode:"search"})` 按需补）；收工只记 lasting 的决策/偏好/坑，不记流水账；`DAILY` 7 天提炼后删。
- L2（opencode-mem 插件）：auto-capture 自动记、首条自动注入；手动用 `memory({mode:"add/search/list/profile/forget"})` 即时存取；跨项目查必须显式 `scope: "all-projects"`。
- 记忆正文不进 AGENTS.md（每次全量注入，塞多等于给每个 token 交税）。
- 每月 10 分钟晋升评审：稳定的提进 AGENTS.md/L1，错的删，shard 水位检查。评审一半时间在处理矛盾记忆 → 启动 L3（Graphiti）。
