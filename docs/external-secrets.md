# 外部 Secrets：生产 Infisical Operator；预检 ephemeral（#317 adopt-list）

## 生产：Infisical Operator（已落地）
- `infisical` ns：`infisical-opera-controller-manager` 1/1 Running；Infisical server/postgres/redis 正常。
- CRD：`infisicalstaticsecrets.secrets.infisical.com`、`infisicalstaticsecretpushes.secrets.infisical.com`。
- 各 ns 以 **InfisicalStaticSecret** 声明式生成 Secret（仓库零明文）：
  - `erpnext/erpnext-secrets`
  - `litellm/litellm-secrets`
  - `opencode-team/opencode-team-secrets`、`opencode-team/browserless-secrets`
  - `opencode-xieyucheng/opencode-xieyucheng-secrets`
  - `opencode-yingxin/opencode-yingxin-secrets`
  - `kube-system/traefik-edge-secrets`

**验证命令**：
```bash
kubectl get infisicalstaticsecrets -A
kubectl -n opencode-team get secret opencode-team-env
```

## 预检（bake-stack）：ephemeral，不是生产 Secrets 路径
- 预检在 **ephemeral k3d** 里用 `kubectl create secret --from-env-file` 现造 Secret，只为让 e2e Pod 起得来；
  ephemeral 集群没有 Infisical 后端，**故不引入 ExternalSecret**。
- 该 Secret 随 k3d 销毁，不入仓、不留存；真实密钥仍由 Infisical Operator 在生产集群注入。
- 代码位置：`.github/workflows/bake-stack.yml` 的「Secret 预渲染」步骤（已加注释指向本文档）。

## 结论
- **生产**：外部 Secrets 已由 Infisical Operator 接管（可验证）。
- **预检**：ephemeral 测试夹具，明确不纳入生产 Secrets 路径；文档化完成。
