# reloader：stakater/reloader 原样重打（SWR 常驻，digest pin 即版本）。
# 用途：Secret 变更自动 rollout（--reload-strategy=annotations，
# 只重启带 reloader.stakater.com/auto 注解的 Deployment）。
# 版本：RELOADER_TAG（dispatch 传入；默认值只给本地构建兜底，CI 全按参数构建）。
ARG RELOADER_TAG=v1.4.24
# digest pin 即版本（v1.4.24 多架构 manifest，2026-11-24 解析）；bump = 改 tag 与 digest。
FROM ghcr.io/stakater/reloader:${RELOADER_TAG}@sha256:3ab43d3eb96c59798644bf826b0444a846c0197d22ab4b6c101c4da3e1d6ef23
