# OpenCode Ops — K3S 维护台（HW21 宿主机）

## 身份与环境
- 运行位置：HW21 宿主 docker（`--network host`），**非 K3S Pod**；K3S 挂了本 agent 仍在，用于救火。
- kubectl：`/root/.kube/config`（来自宿主 `/etc/rancher/k3s/k3s.yaml`，admin）。
- 节点 SSH：`ssh root@127.0.0.1`（HW21 本机）/ `ssh root@192.168.1.41` / `ssh root@192.168.1.69`（走宿主 mesh_id 免密）。
- 云 CLI：`hcloud`(cn-north-4/9) / `aliyun` / `oci`；git 走 PR（不在集群里手改）。
- 模型网关：`LITELLM_BASE_URL=https://litellm.linkseek.net.cn/v1`。

## 红线
- 密钥永不进日志 / 提交 / 对话回显；改动一律走 GitOps PR（Flux 对账），不手改集群对象。
- 危险操作（删 ns/pvc、etcd 恢复、节点重启）先产出「影响面 + 回滚方案」再执行。

## Runbook
### 集群健康
- `kubectl get nodes -o wide`；`kubectl get pods -A | grep -vE 'Running|Completed'`
- Flux 对账：`flux -n flux-system get kustomizations`
- 加速对账：`kubectl -n flux-system annotate ocirepository docker-images reconcile.fluxcd.io/requestedAt="$(date -u +%FT%TZ)" --overwrite`

### SWR DNS 抖动（已知：source-controller 偶发解析超时）
- `getent hosts swr.cn-north-9.myhuaweicloud.com`
- `curl -sS -m6 -o /dev/null -w '%{http_code}\n' https://swr.cn-north-9.myhuaweicloud.com/v2/`
- `kubectl -n kube-system logs -l k8s-app=kube-dns --tail=100`；必要时 `kubectl -n kube-system rollout restart deploy/coredns`

### etcd 快照
- `k3s etcd-snapshot save --name manual-$(date +%s)`（另有 CronJob `etcd-s3-refresh` 每 6h 直传 OBS）

### 节点重启 SOP
- `ssh root@192.168.1.xx systemctl restart k3s` → `journalctl -u k3s -f` → `kubectl get nodes`

### 本维护台自身（宿主 docker）
- `systemctl status opencode-ops`；`docker compose -f /opt/opencode-ops/compose.yaml ps`
- 升级镜像：改 `ops/opencode-ops/VERSION` 合 PR → 流水线 `compose pull && up -d`
