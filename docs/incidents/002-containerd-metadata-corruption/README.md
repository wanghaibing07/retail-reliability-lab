# Incident #002: containerd metadata corruption after unexpected power loss

## Summary

宿主机发生非正常断电后，k8s-worker2 上的 containerd 无法稳定运行。

containerd 在恢复历史 sandbox 和 overlayfs snapshot 状态时持续发生 bbolt panic，
导致 containerd crash loop，并进一步影响 Flannel 和该节点上的业务 Pod。

## Impact

受影响节点：

- k8s-worker2

主要现象：

- containerd 反复退出和自动重启
- 多个 Pod 状态变为 Unknown
- Flannel Pod 无法正常运行
- `/run/flannel/subnet.env` 缺失
- Pod sandbox 无法建立网络
- 部分 Service 丢失 Ready Endpoint
- Retail 业务出现访问异常

## Timeline

- 宿主机发生非正常断电，虚拟机恢复后 worker2 的 containerd 开始反复退出。
- containerd 在恢复历史 sandbox 和 overlayfs snapshot 状态时触发 bbolt panic。
- kubelet 仍在尝试管理节点，但运行时不稳定，多个业务 Pod 进入 `Unknown`。
- Flannel 因 `/run/flannel/subnet.env` 缺失无法完成 Pod 网络初始化。
- 隔离 worker2、保存故障现场后重建 containerd root，随后重启 kubelet 和 Flannel。
- 节点、运行时、Pod、Service Endpoint 和业务 HTTP 均恢复后解除 cordon。
## Key Evidence

containerd 出现：

```text
panic: page 116 already freed
```

调用栈涉及：

```text
go.etcd.io/bbolt.(*Tx).Commit
containerd snapshots MetaStore
overlay snapshotter createSnapshot
```

同时观察到：

```text
failed to recover sandbox state
unable to find sandbox ... not found

failed to unmarshal sandbox spec
type with url : not found

failed to rename
.../snapshots/new-*
.../snapshots/365:
file exists
```

Flannel / CNI 随后出现：

```text
failed to load flannel 'subnet.env' file:
open /run/flannel/subnet.env:
no such file or directory
```

## Root Cause Assessment

宿主机非正常断电后，containerd 的 bbolt / overlayfs snapshot
本地运行时状态出现不一致。

现有证据能够证明 containerd metadata 与 snapshot 状态异常，
但无法证明异常断电是唯一可能原因，因此不将其描述为确定的唯一根因。

## What Was Ruled Out

调查中未发现以下因素是本次故障的主要原因：

- Retail 应用镜像或业务进程本身损坏
- Kubernetes Service 配置错误
- 单纯的业务清单变更
- 持续性的磁盘 I/O 错误
- 需要保留的 StatefulSet/PV 数据被误删

这些判断基于现场日志、磁盘检查和恢复后的分层验收；它们不等于证明所有潜在基础设施因素都不存在。
## Recovery

恢复前确认：

- worker2 没有必须保留的唯一业务数据
- 文件系统与磁盘没有持续 I/O 错误

执行：

1. cordon worker2
2. 停止 kubelet 与 containerd
3. 保留 containerd 故障数据库和配置作为证据
4. 将损坏的 `/var/lib/containerd` 整体隔离
5. 创建新的 `/var/lib/containerd`
6. 启动并验证 containerd 稳定
7. 启动 kubelet
8. 等待 Flannel 重新生成 `/run/flannel/subnet.env`
9. 恢复业务工作负载
10. uncordon worker2

恢复后：

- containerd `NRestarts=0`
- CRI 正常
- Flannel Ready
- worker2 Ready
- Retail Workloads Ready
- Service Ready Endpoints 恢复
- 业务 HTTP 返回 200

## Lessons Learned

- Node Ready 不代表 container runtime 一定健康
- containerd 本地状态与 Kubernetes 控制面期望状态是两层不同状态
- 无状态 Worker 的损坏运行时状态可通过隔离并重建 containerd root 恢复
- StatefulSet / PV 必须在清理运行时前确认数据位置
- 故障恢复必须验证业务 HTTP，而不是只检查 Pod Running
- containerd 故障现场应先备份后清理

## Follow-up Actions

- 为三台 VM 建立可重复的正常关机、启动和节点 Ready 检查流程。
- 将 containerd、Flannel 和节点级恢复证据纳入故障演练清单。
- 对需要持久化的数据先核对 PV、备份和恢复路径，再决定是否隔离运行时目录。
- 为 containerd bbolt、snapshotter、kubelet 和 CNI 异常增加集中化日志或采集脚本。
- 将“运行时恢复”与“业务 HTTP 验收”保留为两个独立检查点，避免只看到 Node Ready 就宣布恢复。
