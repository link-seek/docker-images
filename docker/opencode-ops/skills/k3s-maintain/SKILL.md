---
name: k3s-maintain
description: 维护 link-seek K3S 集群（节点/flux/etcd/网络）的操作手册与安全边界。
---
# k3s-maintain

维护 link-seek K3S 集群的操作手册（详见 image 内 /root/.config/opencode/AGENTS.md）。
要点：admin kubeconfig 在本机；节点走 ssh root@127.0.0.1/192.168.1.41/192.168.1.69（mesh_id 免密）；
改动走 GitOps PR；危险操作先出影响面+回滚。
