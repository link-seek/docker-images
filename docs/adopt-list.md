# adopt-list 决策记录（#317）

| 项 | 结论 | 证据/说明 |
|---|---|---|
| gitleaks 取代自研 hygiene | ✅ 已采用 | docker-images #336 / infra #910；CI `hygiene=pass` |
| kubeconform | ✅ 已采用 | infra #911；CI `kubeconform=pass` |
| Dockerfile 去浮动 | ✅ 已采用 | docker-images #337；skill vendored/obsutil sha/pip-npm pin |
| NFS | ✅ 按官方 NFSv4 伪根重做 | infra #912/#913；provisioner Running/PVC Bound/probe 写成功 |
| 外部 Secrets（生产） | ✅ 已采用 | Infisical Operator（InfisicalStaticSecret）覆盖 erpnext/litellm/opencode-*/browserless/traefik |
| 外部 Secrets（预检） | ✅ 文档化 | ephemeral k3d 夹具；见 docs/external-secrets.md |
| Helm 全量迁移 | ✅ 已采用 | docker-images #339/#340 + infra #915；3 HelmRelease READY |
| cosign/SLSA | ⏭ 按决策不做 | #317 押后项 |

## regsync（镜像同步）—— 评估后保留 skopeo
- 尝试：`scripts/gen_regsync.py` 生成 `images/mirror.yaml` → regsync 配置（creds 用官方 `{{env "..."}}` 模板），
  `regsync once`（regclient v0.11.7）。
- 结果：**SWR 目标 blob POST 持续 `unauthorized`**，即使：
  - 同一 job 内 `skopeo login` 成功；
  - 同一 `SWR_LOGIN_USER/PASS` 用 skopeo 可 push（原同步路径一直可用）；
  - regsync creds 已确认写入配置（日志 `regsync creds: present`）。
  → 判定为 **regclient 与 SWR registry 的 token/push 交互不兼容**（至少当前版本）。
- **决策**：保留 `skopeo` 作为同步引擎（skopeo 本身是社区维护件；自研仅为 `make-public` 的 SWR API 薄壳）。
- **验证**：`mirror-images` 在 main 上 `workflow_dispatch(mode=sync)` 实跑成功（见 #317 评论 run id）。
- 若未来仍要 regsync：需 SWR 侧确认 token 兼容，或改用 regctl 读取 docker config 的凭据链。

> 注：regsync 改动曾误随 #342 并入 main（导致一次 mirror sync 失败），已回退为 skopeo；`scripts/gen_regsync.py` 保留为评估产物，不再在流水线使用。
