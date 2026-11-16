# k8s/opencode — trial 说明（P0→P3）。
# 翻译源：stacks/opencode/hw41/{compose.yml,env-sources.conf} + deploy-opencode-prod-hw41.yml（secret 名）。
# 有意未带（切流 checklist，P4 前补）：./config/home/.aliyun/.oci（HW41 有，.69 无）、
# /old-workspace（历史业务只读）。
# tailscale-state 已持久化（ts-state 1Gi PVC；此前 emptyDir+reusable key 致 hostname 漂移 -1/-2，#340 定位）。
# trial verify 只认簇内 200（E2E 在 P4 经 Caddy）。
