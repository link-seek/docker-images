# browserless-cjk：开源 browserless/chromium 单浏览器镜像 + 中文字体（独立 Pod 部署用）。
# 用法：docker build --build-arg BROWSERLESS_TAG=<版本> -f Dockerfile.browserless-cjk -t <镜像> .
# 背景：原生 ghcr.io/browserless/chromium 无 CJK 字体，中文截图 tofu；企业版 registry 要 license，
# 开源版 SSPL 自建可用（部门内部用合规，见 browserless#licensing）。
# 版本 pin：BROWSERLESS_TAG（dispatch 必填）+ 底座 digest 由 FROM tag digest 锁定（转正时以 run 日志 digest 为准）。
# 底座为 Ubuntu 24.04（v2.56 实测），apt 装 fonts-noto-cjk + emoji 后 fc-cache。
# 注意：CI 全按 dispatch 必填参数构建，不读这里默认值；默认值只给本地 docker build 兜底。
ARG BROWSERLESS_TAG=2.63.1
# 底座 digest pin（v2.63.1 多架构 manifest，2026-11-24 解析）；bump = 改 tag@digest 这行。
FROM ghcr.io/browserless/chromium:v2.64.4@sha256:cee2fee0b7c92dfb70f0ab0738801a358b8548e5fdb954d5ca9315e459d11a71

USER root
SHELL ["/bin/bash", "-c"]

# 中文字体（约 +60M deb + cache；日文假名/韩文附带，不拆包省事）。
# 非交互防卡 + 只装推荐依赖（--no-install-recommends，浏览器本体不动）。
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      fonts-noto-cjk fonts-noto-color-emoji fontconfig \
    && rm -rf /var/lib/apt/lists/* \
    && fc-cache -f \
    && fc-list | grep -ci "noto.*cjk"

# 切回原运行用户（v2 镜像为 blessuser；若上游改名构建即红，fail-closed）。
USER blessuser

# 端口/健康沿用上游：3000 + /pressure（k8s 探针打这个）+ TOKEN 鉴权（空 TOKEN 则随机，不可取）。
EXPOSE 3000
