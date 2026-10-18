# docker-images

自用派生镜像的构建与发布。第一条流水线：OpenDesign（含固定版本 OpenCode CLI）。

## 镜像

| 镜像 | 说明 |
| --- | --- |
| `ghcr.io/link-seek/opendesign:<od>-oc<oc>`（+ `latest`）| 官方 `ghcr.io/nexu-io/od` + 固定版 `opencode` 二进制 + `--dir` shim，开箱即用，不再挂宿主机 CLI |
| `swr.cn-north-9.myhuaweicloud.com/xieyucheng123/opendesign`（同 tag）| 国内加速镜像（SWR 华北九区组织数配额满，暂用个人命名空间） |

## 为什么 OpenCode 版本要 pin 死

OpenDesign 调 CLI 参数是按版本写死的（如 `--dir`、`--pure`），新版 opencode 会直接报错
（`Unrecognized flag: --pure`，`--dir` 靠 shim 硬转）。所以 `OPENCODE_TAG` 默认 pin 在
`Dockerfile.opendesign` 里（当前 `2.0.6` 配 `OD 0.24.1`），流水线只巡检 OD 上游，不跟 opencode 最新版。

升级 opencode 的唯一入口：手动 `workflow_dispatch` 传 `opencode_tag`，并先在测试容器里确认
daemon 日志 `test:agent ... ok` 再切生产。

## 本地用法（HW21）

```yaml
# compose.yml：image 换掉；opencode 的 bind mount 已删（CLI 烘进镜像了）；
# home 卷保留；LITELLM_* 走 .env（600 权限，不进仓库）
services:
  opendesign:
    image: swr.cn-north-9.myhuaweicloud.com/xieyucheng123/opendesign:0.24.1-oc2.0.6
    env_file:
      - /root/opendesign/.env   # LITELLM_BASE_URL=http://100.91.222.51:4000（容器内 host.docker.internal 不解析）+ LITELLM_API_KEY
    volumes:
      - od-data:/app/.od
      - /root/opendesign/home:/home/open-design
```

说明：
- 镜像里 `OPENCODE_CONFIG=/app/opencode/opencode.json`（默认 `opencode-go/muse-spark-1.3-contributor`，
  内容镜像自 `xieyucheng123/opencode` 的 `docker/opencode.jsonc`，那边改了这边同步改）。
  放在 `/home/open-design` 之外是因为该目录会被宿主机 home 挂载遮住。
- OD 选 Default（不传 `-m`）→ 走 jsonc 默认 muse-spark；OD 显式选模型（传 `-m`）→ 走网关对应模型。
  注意网关侧各模型协议不同（如 muse-spark 只支持 responses，走 OD 传 `-m` 的 chat 路径会 400），
  换默认模型前先用 `docker exec <c> opencode run` 验证。

## 手动触发

Actions → od-image → Run workflow，可指定 `od_tag` / `opencode_tag` / `force`。
外部巡检可用 `repository_dispatch`（event type `upstream-od-image`，payload `{"tag": "0.25.0"}`）。

## opencode-tools（glibc 线）

第二条流水线：`Dockerfile.opencode-tools` + `docker-tools.yml` + `test-memory.yml`。

```text
opencode.ai/files/bin/<tag>/opencode-linux-<arch>.tar.gz（官方 v2 二进制，glibc）
  → ubuntu:24.04 底座 → 云 CLI/运行时 → 烘焙配置 → RUN plugin add（记忆插件）
  → ghcr.io/link-seek/opencode-tools:<tag> + :latest
  → SWR north-9 xieyucheng123（同名，直推）
```

为什么不用官方镜像（Alpine/musl）：opencode-mem 的 onnxruntime/turso 原生件缺
`fcntl64`，musl 上启动即死且静默（2026-10 实证）。glibc 线是记忆系统的前提。

* 版本：`OPENCODE_TAG`（默认见 Dockerfile）、`OPENCODE_MEM_VERSION`（与
  `docker/opencode-tools/opencode.jsonc` 同值，CI 一致性检查）。
* 跟随：每周一扫 anomalyco git tag（v2.0.x，超 3 天＋二进制资产存在才打），`force` 重打。
* 回写：`.upstream-tools-tag`＋Dockerfile pin 前移，main 留痕。
* 测试：`test-memory.yml`（opencode＋烘入插件＋网关＋Ollama 跨会话召回、工具 parity 矩阵、
  烘焙文件密钥卫生扫描）全绿才算交付。
* 部署侧（compose/`.env`/pin）在 infra 仓，本仓只管构建。

## 手动触发

Actions → tools-image → Run workflow，可指定 `opencode_tag` / `force`。

## 铁律：打包仓 vs 部署仓分工（2026-10-18，与 infra 仓 README 同源）

- **本仓对运行结果负责**：业务逻辑（guard、passthrough、auth、重试、默认配置、插件 bake）全部进镜像，digest 即行为版本号。部署侧只认 digest，不认过程。
- **部署仓（`link-seek/infra`）只对送达负责**：compose pin digest + env 引用 → `up` 即部署，无业务逻辑。
- **测试对象是镜像**：CI 拉 digest pin 跑 e2e；**回滚 = 换 digest 发 PR**，git 历史即备份。
