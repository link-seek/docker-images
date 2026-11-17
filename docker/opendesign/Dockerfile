# 派生镜像：在官方 OpenDesign 镜像上 bake 固定版本 OpenCode CLI
# 用法：docker build --build-arg OD_TAG=<od版本> --build-arg OPENCODE_TAG=<opencode版本> -f Dockerfile.opendesign -t ghcr.io/link-seek/opendesign:<tag> .
# 注意：OPENCODE_TAG 必须和 OD 版本对死（OD 调 CLI 参数按版本写死，如 --dir/--pure），不要跟最新版，见 README。
ARG OD_TAG=0.24.1
ARG OPENCODE_TAG=2.0.6
FROM ghcr.io/anomalyco/opencode:${OPENCODE_TAG} AS oc
FROM ghcr.io/nexu-io/od:${OD_TAG}

USER root

# opencode musl 二进制的运行时依赖（OD 底座 node:24-alpine，自带 apk；与官方 opencode Dockerfile 要的包一致）
RUN apk add --no-cache libgcc libstdc++ ripgrep

# 从官方 opencode 镜像取 musl 二进制，改名 opencode-real（OD 调的是 /usr/local/bin/opencode，即下面的 shim）
COPY --from=oc /usr/local/bin/opencode /usr/local/bin/opencode-real
# --dir 转 cd 的 shim（OD 0.24.x 调用的 opencode 2.0.6 没有 --dir flag），原文件见 docker/opencode-shim
COPY docker/opencode-shim /usr/local/bin/opencode
RUN chmod +x /usr/local/bin/opencode /usr/local/bin/opencode-real \
 && /usr/local/bin/opencode-real --version \
 && /usr/local/bin/opencode --version

# opencode 默认配置（model + provider，只引用 env，不含密钥，见 docker/opencode.jsonc，
# 内容镜像自 xieyucheng123/opencode fork 的 docker/opencode.jsonc）。
# 注意：必须放在 /home/open-design 之外——该目录运行时会被宿主机 home 挂载遮住。
# OPENCODE_CONFIG 的优先级介于全局与项目配置之间；OD 传 -m 时照常用 -m 的模型，
# OD 选 Default（不传 -m）时落到这里的 opencode-go/muse-spark-1.3-contributor。
# LITELLM_BASE_URL / LITELLM_API_KEY 由宿主机 .env 经 compose env_file 注入（涉密不进镜像）。
COPY docker/opencode.jsonc /app/opencode/opencode.json
ENV OPENCODE_CONFIG=/app/opencode/opencode.json

USER open-design
