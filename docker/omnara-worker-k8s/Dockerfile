# omnara-worker-k8s：fork kubernetes-provider 分支源码构建（含 Plain Pod machine provider）。
# 对齐上游 Dockerfile 的 worker 段；仅构建上下文换成 fork 指定 ref。
ARG FORK_BRANCH=kubernetes-provider
ARG FORK_SHA=""
# worker-tools：在 fork 源码上下文内构建 chroot 运行时（file-tools 的输入）。
# 与上游 Dockerfile 的 file-tools 段同义，只是 FROM 换成已含源码的 go-base。
ARG FORK_BRANCH=kubernetes-provider
ARG FORK_SHA=""
FROM golang:1.27.4-bookworm@sha256:4fa7c968ba93f1635670522dbb01a2c78150443e1385746924566079f36570ea AS worker-tools
ARG FORK_BRANCH
ARG FORK_SHA
WORKDIR /src
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates ripgrep sed libcap2-bin \
 && rm -rf /var/lib/apt/lists \
 && git init -q . && git remote add origin https://github.com/xieyucheng123/omnara.git \
 && git fetch -q --depth 50 origin "${FORK_BRANCH}" \
 && if [ -n "${FORK_SHA}" ]; then git checkout -q "${FORK_SHA}"; else git checkout -q FETCH_HEAD; fi \
 && go mod download && mkdir -p /out/memory
ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -o /out/omnara-chroot-sandbox ./cmd/chroot-sandbox
COPY cmd/chroot-sandbox/install.sh /src/chroot-sandbox/install.sh
RUN sh /src/chroot-sandbox/install.sh /src/omnara-chroot-sandbox /out

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

FROM go-base AS worker-build
ARG TARGETOS
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -o /out/omnara-worker ./cmd/worker \
 && CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -o /out/omnara-sandbox ./cmd/sandbox \
 && CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -o /out/omnara-chroot-sandbox ./cmd/chroot-sandbox

FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS file-tools
RUN --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends ripgrep sed libcap2-bin
# chroot 运行时文件来自 fork 内构建的 worker 产物（file-tools 必须在 fork 上下文里跑，见 Dockerfile.worker-tools）。
COPY --from=worker-tools /out/ /
FROM gcr.io/distroless/cc-debian13:nonroot@sha256:cb87acc574abe719b6e5c547384defa2f7b1f24af9605d3f618cf852495d8be2 AS worker
WORKDIR /app
ADD --chmod=0444 https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /etc/ssl/rds-global-bundle.pem
COPY --from=file-tools /usr/bin/rg /usr/local/bin/
COPY --from=file-tools /usr/lib/*-linux-gnu/libpcre2-8.so.0 /usr/lib/
COPY --from=go-base --chown=nonroot:nonroot /out/memory /var/lib/omnara/memory
COPY --from=worker-build /out/omnara-worker /out/omnara-sandbox /usr/local/bin/
COPY --from=file-tools /out/ /
ENTRYPOINT ["/usr/local/bin/omnara-worker"]
