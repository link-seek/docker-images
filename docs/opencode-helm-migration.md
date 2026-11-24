# opencode 主部署 Helm 迁移（#317 Phase 2 剩余）

目标：把 `k8s/opencode-team`、`k8s/opencode-xieyucheng`、`k8s/opencode-yingxin` 三份清单
归一为 **1 个 chart + 3 份 values**（`charts/opencode`），由 Flux `HelmRelease` 下发，
版本交给 Renovate。**先归一结构，再切 Flux**（避免 chart 里塞满 if）。

## 现状差异（需归一/参数化）
| 维度 | team | xieyucheng | yingxin |
|---|---|---|---|
| image | opencode-team@digest | opencode-tools@digest | opencode-tools@digest |
| 容器名 | opencode | opencode | opencode-yingxin |
| initContainer | root-home-seed（seed /root） | init-dirs | init-dirs |
| securityContext | SSH 加固（SETUID…） | 默认 | 默认 |
| volumes | prod-work/prod-data/root-home/tmp | prod-work/prod-data（+?） | prod-work/prod-data（+?） |
| nodeSelector | zhangzhirui | xieyucheng-langfuse | 无 |
| 额外 env | OBS/MAAS/OPENCODE_SERVER_USERNAME | HCLOUD/ALI | — |
| browserless | 1（共享实例） | 0 | 0 |
| Services | opencode + browserless + opencode-vpc | opencode + opencode-vpc + browserless | opencode-yingxin + opencode-vpc + browserless |
| RBAC | rbac.yaml（小） | rbac.yaml（大，108 行） | 无 rbac.yaml |
| entrypoint ConfigMap | 67 行 | 42 行 | 42 行 |
| IngressRoute | 29 行 | 19 行 | 22 行 |

## 归一决策（落地前需确认/统一）
1. **RBAC 取并集**：以 xie 的 108 行为基线（tools 需要），team/ying 也用同一份（最小可用集需核对）。
2. **entrypoint 统一**：抽出公共脚本，差异用 env（`SSH_ENABLE` 等）；或 chart values 传脚本。
3. **securityContext**：team 的 SSH 加固作为 `ssh.enabled=true` 时的固定块；其余默认。
4. **initContainer**：`init.mode=seed-root|dirs`（team=tools？按镜像能力定）。
5. **browserless**：`browserless.enabled`（team=true, xie/ying=false；软隔离共享已上线）。
6. **opencode-vpc**：`vpc.enabled`（team/xie/ying 都有？按实际）。

## 目标 chart values（草案）
```yaml
name: opencode
namespace: opencode-team
image: {repository, digest}
containerName: opencode
nodeSelector: {kubernetes.io/hostname: ...}
paths: {work, data, rootHome?}
ssh: {enabled, capabilities}
init: {mode: seed-root|dirs}
env: [...]
extraSecretEnv: [...]
browserless: {enabled, replicas}
service: {name, port}
vpc: {enabled, port, sshPort}
rbac: {enabled}
ingress: {enabled, host, tlsSecret}
entrypoint: {script}
```

## 迁移步骤
1. 归一 RBAC/entrypoint/securityContext（先出 PR，保持渲染等价）。
2. 建 `charts/opencode`（Deployment/Service/IngressRoute/RBAC/ConfigMap 模板 + `values-{team,xie,ying}.yaml`）。
3. `helm template` 三方渲染，与现有 `kubectl kustomize` 输出做**字段级 parity**（脚本）。
4. infra 新增 `apps-opencode-{team,xie,ying}` 的 `HelmRelease`（`dependsOn` 已有 ns/secret），
   同一 PR 内移除对应 `apps-*` Kustomization，避免双 reconciler 抢对象。
5. 退役 docker-images `k8s/opencode-*`（保留 `_preflight` 或迁移到 infra）。
6. Renovate 管 chart 版本（`helmv3`/OCI）。

## 风险
- 双 reconciler 抢同一对象（Kustomization ↔ HelmRelease）：切换必须原子、先切后删。
- 预检（bake）当前读 docker-images `k8s/_preflight`；清单迁移后需改 `k8s_manifest_repo/path`。
- entrypoint/RBAC 归一若与现网行为不一致，可能影响 SSH/工具权限 → 需 parity 验证。

## 落地记录（PR1→PR2→PR3）
- PR1：`_helpers.tpl`（REC labels）+ `rbac.create`/`serviceAccount` 开关；k8s 源同步加注；parity 全绿。
- PR2：values 瘦身（文档化默认 + 三实例差异）+ 模板按 kind 拆分 + `values.schema.json`；
  parity 退役→`helm lint` + kubeconform；bake 预检改 YAML 感知替换；Chart 0.1.0→0.2.0。
  渲染等价：team 全同；xie/ying 仅 entrypoint TS 注释归一。
- PR3：删 `k8s/opencode-*` 与 `_preflight/opencode-*` overlay；bake caller 去 kustomize 遗留输入；
  README/intake 示例路径更新。Flux 只走 HelmRelease（chart 0.2.0）。
