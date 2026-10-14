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
