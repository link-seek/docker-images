# 协作分工（2026-11-16：机器人写码，人只审合）

- 写码优先走仓库机器人（coding agent 出 PR）；OpenCode 默认只做合码前审阅，不直接动手改。
- 人只负责审 PR + 点 merge；机器人 PR 必须写清影响面与回滚法。
- 例外：机器人搞不定、线上救火，人点名 OpenCode 才动手。

# 本仓定位

本仓是组织镜像工厂（构建纪律归工厂），各线归属消费方（归属见 docker/OWNERS.yaml）：业务线归商家，底座线归 infra。

商家对运行结果负责：业务逻辑 + 镜像 + manifest + 配送闭环，digest 即行为版本号；manifest 跟镜像走，同一仓同一 PR。镜像只经 GH 流水线打包（bake-tools），不在本地手打。
构建细则按线分读：tools 线见 `docker/opencode-tools/AGENTS.md`，team 线见 `docker/opencode-team/AGENTS.md`（两线各自独立维护，勿互相照抄）。
