# Stage 4：诊断 PromQL 查询集

这四组查询用于告警后的定位，不等同于仪表盘，也不把所有指标都变成告警。先从症状开始，再向下定位。

## 1. 业务可用性

```promql
up{job="retail-ui-nodeport"}
```

```promql
probe_success{job="retail-ui-nodeport"}
```

```promql
probe_http_status_code{job="retail-ui-nodeport"}
```

```promql
kube_deployment_spec_replicas{namespace="retail"}
-
kube_deployment_status_replicas_available{namespace="retail"}
```

```promql
kube_statefulset_replicas{namespace="retail"}
-
kube_statefulset_status_replicas_ready{namespace="retail"}
```

首页 HTTP 200 只代表入口探测成功，不代表下单交易或数据库恢复能力。

## 2. GitOps 状态

```promql
argocd_app_info{name=~"retail|observability"}
```

```promql
argocd_app_condition{name=~"retail|observability"} == 1
```

```promql
up{job=~"argocd-application-controller|argocd-server|argocd-repo-server"}
```

先区分 Application 本身 OutOfSync/Degraded，还是 Argo CD 组件抓取异常。

## 3. 节点与 Workload

```promql
kube_node_status_condition{condition="Ready",status="true"}
```

```promql
kube_pod_status_phase{namespace=~"retail|observability",phase=~"Pending|Failed|Unknown"} == 1
```

```promql
kube_deployment_spec_replicas{namespace=~"retail|observability"}
-
kube_deployment_status_replicas_available{namespace=~"retail|observability"}
```

```promql
kube_statefulset_replicas{namespace="retail"}
-
kube_statefulset_status_replicas_ready{namespace="retail"}
```

当前 kube-state-metrics 只采 Node、Pod、Deployment、StatefulSet 对象状态，因此这里不声称具备节点 CPU、内存或磁盘容量指标。

## 4. 监控系统自身

```promql
up{job=~"alertmanager|blackbox-exporter|kube-state-metrics|argocd-application-controller|argocd-server|argocd-repo-server|prometheus"}
```

```promql
blackbox_exporter_config_last_reload_successful
```

```promql
prometheus_rule_evaluation_failures_total
```

```promql
ALERTS{alertstate=~"pending|firing"}
```

Alertmanager 的通知失败告警暂不加入 Stage 4 规则集：在当前现场证据中尚未确认具体失败指标及其正常基线。后续只有当该指标实际存在且能解释时再增加。
