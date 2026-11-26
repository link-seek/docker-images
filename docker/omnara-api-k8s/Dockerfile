# omnara-api-k8s：fork xieyucheng123/omnara `kubernetes-provider` 分支源码构建
#（含 Plain Pod machine provider，未合上游前的试用镜像）。
# 对齐上游 Dockerfile 的 api 段（go-base→api-build→mcp 快照→distroless runtime），
# 仅把构建上下文换成 fork 指定 ref；行为差异只有新增的 kubernetes provider。
# 版本 pin：FORK_BRANCH（分支）+ FORK_SHA（commit sha，空=分支尖）；
# dispatch 传入精确 sha 可复现，转正以 run 日志 digest 为准。
ARG FORK_BRANCH=kubernetes-provider
ARG FORK_SHA=""
FROM golang:1.27.4-bookworm@sha256:4fa7c968ba93f1635670522dbb01a2c78150443e1385746924566079f36570ea AS go-base
ARG FORK_BRANCH
ARG FORK_SHA
WORKDIR /src
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists \
 && git init -q . && git remote add origin https://github.com/xieyucheng123/omnara.git \
 && git fetch -q --depth 50 origin "${FORK_BRANCH}" \
 && if [ -n "${FORK_SHA}" ]; then git checkout -q "${FORK_SHA}"; else git checkout -q FETCH_HEAD; fi \
 && go mod download && mkdir -p /out/memory

FROM go-base AS api-build
ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -o /out/omnara-api ./cmd/api

FROM go-base AS mcp-registry-snapshot
RUN go run ./tools/mcp-registry-sync -out /out/mcp-registry.json

FROM gcr.io/distroless/static-debian13:nonroot@sha256:8ce6dd87e9823c5b48dcfb2c8604714ccb351ce59607327bcc4957448da279b5 AS runtime
WORKDIR /app
ADD --chmod=0444 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /etc/ssl/rds-global-bundle.pem

FROM runtime AS api
COPY --from=go-base --chown=nonroot:nonroot /out/memory /var/lib/omnara/memory
ENV OMNARA_WEB_SERVING=disabled
ENV OMNARA_MCP_REGISTRY_SNAPSHOT_PATH=/app/mcp-registry/mcp-registry.json
COPY --from=api-build /out/omnara-api /usr/local/bin/omnara-api
COPY --from=mcp-registry-snapshot --chown=nonroot:nonroot /out/mcp-registry.json /app/mcp-registry/mcp-registry.json
ENTRYPOINT ["/usr/local/bin/omnara-api"]
