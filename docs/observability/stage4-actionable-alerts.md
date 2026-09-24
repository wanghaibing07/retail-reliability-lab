# Stage 4：可行动告警与诊断查询验收（2026-09-24）

时区：北京时间 UTC+08:00。以下运行态来自用户在实验集群提供的终端结果。

## 变更

PR #39 在现有 `RetailUIProbeFailed` 之外增加三条平台类告警：

- `MonitoringTargetDown`
- `KubernetesNodeNotReady`
- `ArgoApplicationUnhealthy`

同时增加：

- 三条规则的 promtool 时序行为测试
- Stage 4 平台告警 Runbook
- 四组诊断 PromQL：业务可用性、GitOps、节点/Workload、监控系统自身

未增加 CPU/内存/磁盘阈值告警、restart 计数告警，也未在缺少明确失败指标基线时增加 Alertmanager 发送失败告警。

## 运行态验收

2026-09-24 20:10 CST：

- observability Application revision：`3627456dd5a1671d63e23daa2f7eb16afe371c06`
- Argo CD：Synced / Healthy
- Prometheus Pod：`prometheus-6f47889c97-knntr`
- Prometheus：1/1 Ready，Running，0 Restarts，位于 `k8s-worker2`

四条 Stage 4 告警均成功加载且当前正常：

- `RetailUIProbeFailed`：health=ok，state=inactive
- `MonitoringTargetDown`：health=ok，state=inactive
- `KubernetesNodeNotReady`：health=ok，state=inactive
- `ArgoApplicationUnhealthy`：health=ok，state=inactive

规则评估失败：

- `retail-ui` group = 0
- `stage4-platform` group = 0

Prometheus 当前 8 个监控 target 全部 `up=1`：

- alertmanager
- argocd-application-controller
- argocd-repo-server
- argocd-server
- blackbox-exporter
- kube-state-metrics
- prometheus
- retail-ui-nodeport

当前 `ALERTS{alertstate=~"pending|firing"}` 为空。

## 结论

S4-D 完成。告警规则已通过 CI 中 promtool 规则检查与行为测试，并在真实 Prometheus 中完成加载验证；当前无规则评估错误、无活动告警，监控与 GitOps 目标均健康。

下一步进入 S4-E：在最终稳定配置上进行自然 24h 观察，并记录开始/结束时间、样本覆盖、期间 target/告警状态、最终 Git/Argo revision 和已知限制。该观察不主动制造故障。
