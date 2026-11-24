# nfs-server：Alpine + nfs-utils 的 NFSv4-only 内核服务端（自打，digest pin 即版本）。
# 用途：nfs-subdir-external-provisioner 的后端，给 Omnara memory-data 提供 RWX。
# 实测约束见 run.sh 头注（-N 2 非法；需 mount nfsd）。
# 为什么自打：上游 itsthenetwork/nfs-server-alpine 只有 latest 可用（本仓禁 latest），
# 自打则 base 钉死、可复现。NFSv4-only，单 export（/exports），provisioner 按 PVC 建子目录。
# 运行要求：privileged（内核 nfsd 必需），见 infra k8s/nfs/。
ARG ALPINE_TAG=3.22.1
# digest pin 即版本；bump = 同时改 tag 与 digest（3.22.1@sha256:4bcff639…，2026-11-24 解析）。
FROM docker.io/library/alpine:${ALPINE_TAG}@sha256:4bcff63911fcb4448bd4fdacec207030997caf25e9bea4045fa6c8c44de311d1
RUN apk update && apk upgrade --no-cache && apk add --no-cache nfs-utils \
 && mkdir -p /exports /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery \
 && chmod 777 /exports
COPY docker/nfs-server/exports /etc/exports
COPY docker/nfs-server/run.sh /run.sh
RUN chmod +x /run.sh
VOLUME ["/exports"]
EXPOSE 2049 111
ENTRYPOINT ["/run.sh"]
