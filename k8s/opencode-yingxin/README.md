# k8s/opencode-yingxin — trial 说明（P0→P3）。
# 翻译源：stacks/opencode/hw41/{compose.yml,env-sources.conf} + deploy-opencode-prod-hw41.yml（secret 名）。
# 有意未带（切流 checklist，P4 前补）：./config/home/.aliyun/.oci（HW41 有，.69 无）、
# /old-workspace（历史业务只读）。
# 容器 TS 身份已摘除（2026-11-17）：pod 不进 tailnet，入网走 operator 代理；ts-state PVC 已无用，待删。
# trial verify 只认簇内 200（E2E 在 P4 经 Caddy）。
