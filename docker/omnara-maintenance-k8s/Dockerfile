# omnara-maintenance-k8s：fork kubernetes-provider 分支源码构建。
# 对齐上游 Dockerfile 的 maintenance 段；仅构建上下文换成 fork 指定 ref。
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

FROM go-base AS maintenance-build
ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -o /out/omnara-maintenance ./cmd/maintenance

FROM gcr.io/distroless/static-debian13:nonroot@sha256:aafe993665bf6200db38a02c11a9351e782a84b6a45e7f33b6695638c88e3931 AS runtime
WORKDIR /app
ADD --chmod=0444 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /etc/ssl/rds-global-bundle.pem

FROM runtime AS maintenance
COPY --from=go-base --chown=nonroot:nonroot /out/memory /var/lib/omnara/memory
COPY --from=maintenance-build /out/omnara-maintenance /usr/local/bin/omnara-maintenance
ENTRYPOINT ["/usr/local/bin/omnara-maintenance"]
