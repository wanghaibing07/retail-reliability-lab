# Stage 4 平台告警：定位和恢复

适用告警：

- `MonitoringTargetDown`
- `KubernetesNodeNotReady`
- `ArgoApplicationUnhealthy`

这些告警用于实验集群的监控链路、节点状态和 GitOps 状态。它们不是完整生产告警体系；全集群断电或 Prometheus 自身完全不可用仍无法依靠集群内链路主动通知。

## 1. MonitoringTargetDown

Prometheus 连续 2 分钟无法抓取以下任一目标时触发：

- Alertmanager
- Blackbox Exporter
- kube-state-metrics
- Argo CD application-controller
- Argo CD server
- Argo CD repo-server

先判断是 Pod、Service/Endpoint 还是网络问题：

```bash
K=/etc/kubernetes/admin.conf

kubectl --kubeconfig="$K" -n observability get pods,svc,endpointslices -o wide
kubectl --kubeconfig="$K" -n argocd get pods,svc,endpointslices -o wide
```

同时查询对应 job 的 `up`。若只有一个 target 为 0，先定位该组件；若多个 target 同时为 0，再检查 Prometheus、DNS、Service 网络和节点状态。不要因为 `up=0` 直接修改业务配置。

## 2. KubernetesNodeNotReady

节点连续 5 分钟没有 `Ready=true` 时触发。

```bash
K=/etc/kubernetes/admin.conf

kubectl --kubeconfig="$K" get nodes -o wide
kubectl --kubeconfig="$K" describe node <node>
kubectl --kubeconfig="$K" get pods -A -o wide --field-selector spec.nodeName=<node>
```

优先看 Node Conditions、kubelet、容器运行时和节点网络。若节点恢复 Ready，先确认关键 Pod 正常调度和目标重新被 Prometheus 抓取，再关闭事件。

## 3. ArgoApplicationUnhealthy

Application 持续 5 分钟 `sync_status != Synced`，或 health 为 `Degraded/Missing/Unknown/Suspended` 时触发。正常短暂 `Progressing` 不单独告警。

```bash
K=/etc/kubernetes/admin.conf

kubectl --kubeconfig="$K" -n argocd get applications retail observability
kubectl --kubeconfig="$K" -n argocd get application <app> -o yaml
```

先读 Application conditions 和资源树，再决定是否需要恢复 Git 声明。自动同步环境优先通过 Git 恢复；不要用现场 `rollout undo` 与 Argo self-heal 长期对抗。

## 恢复确认

恢复后只需要确认：

1. 原告警退出 firing；
2. 对应目标/节点/Application 回到正常状态；
3. Alertmanager 如可用，应收到同一告警的 resolved 通知；
4. 记录发现时间、恢复时间、Git revision 和必要的证据。

不要为已经解释清楚的恢复重复制造同类故障。
