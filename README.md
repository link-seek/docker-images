# docker-images

自用派生镜像的构建与发布。第一条流水线：OpenDesign（含固定版本 OpenCode CLI）。

## 镜像

| 镜像 | 说明 |
| --- | --- |
| `ghcr.io/link-seek/opendesign:<od>-oc<oc>`（+ `latest`）| 官方 `ghcr.io/nexu-io/od` + 固定版 `opencode` 二进制 + `--dir` shim，开箱即用，不再挂宿主机 CLI |
| `swr.cn-north-9.myhuaweicloud.com/link-seek/opendesign`（同 tag）| 国内加速镜像 |

## 为什么 OpenCode 版本要 pin 死

OpenDesign 调 CLI 参数是按版本写死的（如 `--dir`、`--pure`），新版 opencode 会直接报错
（`Unrecognized flag: --pure`，`--dir` 靠 shim 硬转）。所以 `OPENCODE_TAG` 默认 pin 在
`Dockerfile.opendesign` 里（当前 `2.0.6` 配 `OD 0.24.1`），流水线只巡检 OD 上游，不跟 opencode 最新版。

升级 opencode 的唯一入口：手动 `workflow_dispatch` 传 `opencode_tag`，并先在测试容器里确认
daemon 日志 `test:agent ... ok` 再切生产。

## 本地用法（HW21）

```bash
# compose 里把 image 换掉，并删掉 opencode 的两行 bind mount，home 卷和环境变量保留
image: swr.cn-north-9.myhuaweicloud.com/link-seek/opendesign:0.24.1-oc2.0.6
```

## 手动触发

Actions → od-image → Run workflow，可指定 `od_tag` / `opencode_tag` / `force`。
外部巡检可用 `repository_dispatch`（event type `upstream-od-image`，payload `{"tag": "0.25.0"}`）。
