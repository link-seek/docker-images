#!/bin/sh
# NFSv4-only 前台启动：rpcbind → statd → nfsd → mountd（前台守住 PID1）。
set -eu
mkdir -p /exports /var/lib/nfs/rpc_pipefs /var/lib/nfs/v4recovery
chmod 777 /exports
exportfs -rav
rpcbind -w
rpc.statd
rpc.nfsd --no-udp --no-nfs-version2 --no-nfs-version3 8
exec rpc.mountd -F --no-udp --no-nfs-version2 --no-nfs-version3
