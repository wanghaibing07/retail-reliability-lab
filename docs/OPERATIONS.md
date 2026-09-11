# 基线与日常操作

## G0 基线检查

先记录状态，再做安装、升级、删除或故障注入。下面的命令是只读检查：

```bash
kubectl get nodes -o wide
kubectl get namespaces
kubectl get storageclass
kubectl get pvc -A
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp
```

建议把结果保存到 `evidence/`，但删除 Token、内网地址、用户数据和完整日志中的敏感字段。

## StorageClass 如何影响项目

StorageClass 是“PVC 到底由谁、用什么方式提供存储”的规则。项目中的数据库或其他有状态服务如果申请了 PVC，而集群没有可用 StorageClass，PVC 可能保持 `Pending`，Pod 也可能因挂载不到卷而无法进入 `Running`。

即使有 StorageClass，也要检查：

- provisioner 是否真的运行；
- PVC 是否绑定到 PV；
- 卷是否只能在某个节点使用；
- 节点重建后数据是否仍可恢复；
- 回收策略是 `Delete` 还是 `Retain`。

本实验可以使用节点本地动态供给器完成练习，但它不能替代云盘、分布式存储或跨节点复制。数据库数据必须配合备份恢复演练，不能只依赖 PVC。

## 安全操作规则

- 默认使用明确的实验命名空间，例如 `retail-lab`。
- 不直接对所有命名空间执行删除命令。
- 变更前保存 G0 快照，变更后记录 rollout、PVC 和事件状态。
- 故障注入必须有明确的停止条件和清理步骤。
- 发现异常时先保存证据，再重启、扩容或删除 Pod。

## 验证闭环

每次变更至少记录：

1. 变更目的和预期结果；
2. 实际执行的命令或 Git commit；
3. rollout、服务端点、PVC 和事件结果；
4. 偏差、恢复动作和下一步。
