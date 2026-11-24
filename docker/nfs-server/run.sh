#!/bin/sh
# NFSv4 优先前台启动：rpcbind → statd → nfsd → mountd（前台守住 PID1）。
# 注意两点（实测）：
# 1. nfs-utils 2.6.4 的 rpc.nfsd 不接受 -N 2（报 Unsupported version），只能禁 v3；
#    v2 关不掉，但只听 cluster 内网，接受。
# 2. privileged 容器里要先 mount -t nfsd，否则 nfsd 起不来。
set -eu
mkdir -p /exports /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery
chmod 777 /exports
mount -t nfsd nfsd /proc/fs/nfsd 2>/dev/null || true
exportfs -rav
rpcbind -w
rpc.statd
rpc.nfsd -N 3 -U 8
exec rpc.mountd -F
