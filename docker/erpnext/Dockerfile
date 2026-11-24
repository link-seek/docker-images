# docker/erpnext/Dockerfile — erpnext-cn 派生镜像：官方 frappe/erpnext + CJK 字体 + zh_CN。
# 用法：docker build --build-arg BASE_TAG=<版本> -f docker/erpnext/Dockerfile -t <镜像> .
# 派生原因：官方镜像缺 CJK 字体（打印 PDF 中文乱码）+ 默认英文；中文插件后续直接加进本文件。
# 版本 pin：BASE_TAG（dispatch 必填传入）；Dockerfile 默认值只给本地构建兜底，CI 不读。
# base 与产出分仓：base 走 url2hc 中转常驻（link-seek/erpnext），产出走 bake 转正（link-seek/erpnext-cn）。
# 审计靠 bake run 日志（tag/digest），不在仓里记版本。
ARG BASE_TAG=v15.94.1@sha256:7e497eff17c26f9002c701dab9063ad88bc0e0e79644b41cad4778e282d8e594
# digest-exempt: 内部派生 base，BASE_TAG dispatch 即版本（tag 无法静态锁 digest）exp:2027-06-30
FROM swr.cn-north-9.myhuaweicloud.com/link-seek/erpnext:${BASE_TAG}

USER root
SHELL ["/bin/bash", "-c"]

# CJK 字体（打印 PDF 中文必需）+ zh_CN locale；注意：只加字体与 locale，不动 bench 代码。
# 安全基线（Trivy 门）：base 是 Debian 12.2（2023 年），bookworm-security 已有大量高危修复；
# 全量 upgrade（与 team 的定向升级不同：base 欠账太多，digest 即版本，漂移可接受）。
RUN apt-get update && apt-get upgrade -y --no-install-recommends \
    && apt-get install -y --no-install-recommends \
      fonts-noto-cjk fonts-noto-cjk-extra locales \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/^# *zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen && locale-gen zh_CN.UTF-8 \
    && fc-cache -f >/dev/null \
    && fc-list :lang=zh | head -3

ENV LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh LC_ALL=zh_CN.UTF-8

# 回落 base 默认用户（frappe，UID 1000；与 chart podSecurityContext 对齐）。
USER frappe
