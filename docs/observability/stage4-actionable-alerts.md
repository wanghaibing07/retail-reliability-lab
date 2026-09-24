# Stage 4：可行动告警与诊断查询验收（2026-09-24）

时区：北京时间 UTC+08:00。以下运行态来自用户在实验集群提供的终端结果。

## 变更

PR #39 在既有 `RetailUIProbeFailed` 基础上增加三条平台告警：

- `MonitoringTargetDown`
- `KubernetesNodeNotReady`
- `ArgoApplicationUnhealthy`

同时增加四组诊断 PromQL：业务可用性、GitOps 状态、节点/Workload、监控系统自身，并为三条新规则加入 promtool 时序行为测试和统一 Runbook。

## 运行态验收

2026-09-24 20:10 CST：

- observability Application revision：`3627456dd5a1671d63e23daa2f7eb16afe371c06`
- Argo CD：Synced / Healthy
- Prometheus Pod：`prometheus-6f47889c97-knntr`
- Ready：1/1
- Status：Running
- Restarts：0
- Node：`k8s-worker2`

四条 Stage 4 告警规则均已加载且正常：

- `RetailUIProbeFailed`：health=ok，state=inactive
- `MonitoringTargetDown`：health=ok，state=inactive
- `KubernetesNodeNotReady`：health=ok，state=inactive
- `ArgoApplicationUnhealthy`：health=ok，state=inactive

规则评估失败：

- `retail-ui` group：0
- `stage4-platform` group：0

Prometheus 8 个配置 target 全部 `up=1`：

- alertmanager
- argocd-application-controller
- argocd-repo-server
- argocd-server
- blackbox-exporter
- kube-state-metrics
- prometheus
- retail-ui-nodeport

当前没有 pending 或 firing 告警。

## 结论

S4-D 完成。当前告警集保持少而可行动：

- 用户入口症状由 `RetailUIProbeFailed` 覆盖
- 监控/GitOps 抓取异常由 `MonitoringTargetDown` 覆盖
- Kubernetes 节点状态由 `KubernetesNodeNotReady` 覆盖
- Argo CD Application 稳态偏离由 `ArgoApplicationUnhealthy` 覆盖

目前不增加 CPU/内存/磁盘、累计 restart、Alertmanager 通知失败等规则，因为现有证据不足以建立可靠阈值或现场尚未确认相应失败指标。

下一步进入 S4-E：在最终稳定配置上进行自然观察窗口，收集覆盖率、告警状态、资源快照和最终 revision，再封 Stage 4 tag。
