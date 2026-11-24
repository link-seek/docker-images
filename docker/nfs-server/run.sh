#!/bin/sh
# NFSv4-only 前台启动：rpcbind → statd → nfsd → mountd（前台守住 PID1）。
# 注意：nfs-utils 用 -N <vers> 禁版本（--no-nfs-version2 这种写法不存在）。
set -eu
mkdir -p /exports /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery
chmod 777 /exports
exportfs -rav
rpcbind -w
rpc.statd
rpc.nfsd -N 2 -N 3 -U 8
exec rpc.mountd -F
