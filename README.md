# docker-images

自用派生镜像的构建与发布（opencode tools/team 线、browserless、litellm-gateway、erpnext、reloader）。

## opencode-tools（glibc 线）

第一条流水线：`docker/opencode-tools/Dockerfile` + `bake-tools.yml`。

```text
opencode.ai/files/bin/<tag>/opencode-linux-<arch>.tar.gz（官方 v2 二进制，glibc）
  → ubuntu:24.04 底座 → 云 CLI/运行时 → 烘焙配置 → RUN plugin add（记忆插件）
  → ghcr.io/link-seek/opencode-tools:<tag> + :latest
  → SWR north-9 xieyucheng123（同名，直推）
```

为什么不用官方镜像（Alpine/musl）：opencode-mem 的 onnxruntime/turso 原生件缺
`fcntl64`，musl 上启动即死且静默（2026-10 实证）。glibc 线是记忆系统的前提。

* 版本：全由 dispatch 必填传入（`opencode_tag`＋`opencode_mem_version`），CI 不读 Dockerfile 默认值；Dockerfile 默认值只给本地构建兜底。
* 跟随：周一巡检已关，上游更新靠人发现后手点 dispatch 传版。
* 审计：bake run 日志记 tag/digest（90 天）；仓里不记版本（无 sync-back）。
* 测试：dgoss 成品自检＋双 runner 预检＋细测全绿才转正式版。
* 部署侧（compose/`.env`）在 infra 仓，本仓只管构建。

## 手动触发

Actions → bake-tools → Run workflow，必填 `opencode_tag` / `opencode_mem_version`。

## 布局约定（2026-11-16 起）

* Dockerfile 进各自目录：`docker/<名>/Dockerfile`（构建上下文仍是仓根，`docker build -f docker/<名>/Dockerfile .`）。
* `docker/<名>/` 放 hook 与配置（`fine-test.sh`、`goss-bake.yaml`、`preflight-env.conf` 等）。
* `bake-stack.yml` 的 `dockerfile:` 传分目录路径；push 触发 `paths:` 同步改。

## opencode-team（部门共用精简线）

第二条流水线：`docker/opencode-team/Dockerfile` + `bake-team.yml` + `k8s/opencode-team/`。

```text
opencode 官方 v2 二进制（glibc）→ ubuntu:24.04 → gh + agent-browser + mem插件 + 邮件三件套
  → ghcr.io/link-seek/opencode-team:<tag> + :latest
  → SWR north-9 link-seek（同名，直推）
```

* 与 tools 的区别：不要 aliyun/hcloud/oci/wrangler/tailscale/本地 chrome；浏览器走独立 browserless Pod。
* 预检（k3d+Flux，#505）：`k8s_app: opencode`，manifest 同仓 `k8s/opencode-team`；team digest 经 images 注入，
  browserless 取 manifest tag。
* 细测：pod 内 `agent-browser connect ws://browserless:3000/chromium?token=…` → open → snapshot → screenshot → close。

## browserless-chrome-cjk（远程浏览器，独立 Pod）

第三条流水线：`docker/browserless-cjk/Dockerfile` + `bake-browserless-cjk.yml`。

```text
ghcr.io/browserless/chromium:<tag> + fonts-noto-cjk/emoji → ghcr.io/link-seek/browserless-chrome-cjk:<tag>
  → SWR north-9 link-seek（同名，直推）
```

* 仓库名带 chrome：bake-stack 新预检按镜像名含 chrome 抓 sidecar 行做 k3d import，改骨架影响全线，故命名适配。
* 无 k8s 预检：归属 `k8s/opencode-team/`，由 bake-team 的 k3d 预检连带验证；本线细测只验单镜像（pressure + CJK + 截图）。

## bootstrap 顺序（首发）

1. dispatch `bake-browserless-cjk`（`browserless_tag=2.63.1`）→ 转正出 `:2.63.1`/`:latest`。
2. dispatch `bake-team`（`opencode_tag=2.3.0`）→ 预检拉 browserless `:latest`，细测连通后转正。
3. `k8s/opencode-team/deployment.yaml` 改 digest pin 发 PR（manifest 跟镜像走，同一仓同一 PR）。
4. infra 仓加 `clusters/k3s/apps-opencode-team.yaml`（Flux 收编）+ pipeline mint `opencode-team-env` Secret → 对账上线试用。

## 分工：商家 vs 快递（2026-10-18，与 infra 仓 README 同源）

- **商家（本仓 `bake-*`）对产品负责**：业务逻辑（guard、passthrough、auth、重试、默认配置、插件 bake）全部进镜像，digest 即行为版本号。
- **快递（`link-seek/infra` 的 `deliver-*`）只对运输负责**：compose pin digest + env 引用 → `up` 即部署，无业务逻辑，不碰内容。
- **门（`secret-hygiene` / `render-check` 等）只验货**：核密钥卫生与键集合，不碰值。
- **测试对象是镜像**：CI 拉 digest pin 跑 e2e；**回滚 = 换 digest 发 PR**，git 历史即备份。
