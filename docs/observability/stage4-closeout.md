# Stage 4 Closeout：Observability

封板日期：2026-09-27  
实验环境：本地 VMware 三节点 Kubernetes 集群

## 结论

Stage 4 Observability 完成。

本阶段建立了从业务入口、GitOps 控制面、Kubernetes 对象状态到监控组件自身的最小可观测闭环，并验证了告警触发、通知、恢复、历史保留和真实运行态。

本项目不将此次结果描述为生产级高可用监控体系，也不把不连续的历史样本包装成“连续 24h 稳定”。

## 最终能力

### 1. Prometheus

- Prometheus v3.13.3
- 单副本
- 固定在 `k8s-worker2`
- PVC：`prometheus-data`
- StorageClass：`local-path-retain`
- PVC：4Gi / RWO
- TSDB retention：48h
- TSDB size limit：3GB
- 已验证 Prometheus Pod 替换后历史样本仍可查询

### 2. 监控目标

最终 8 个 scrape target：

- prometheus
- alertmanager
- blackbox-exporter
- kube-state-metrics
- argocd-application-controller
- argocd-server
- argocd-repo-server
- retail-ui-nodeport

最终收口时 8 个 target 全部 `up=1`。

### 3. 业务探测

Blackbox Exporter 从 worker1 探测 Retail UI NodePort：

`http://192.168.88.5:32065/`

已验证：

- 正常 HTTP 200
- `probe_success`
- `probe_http_status_code`
- 指标驱动失败判据
- 告警 pending / firing
- Alertmanager firing 邮件
- 恢复后的 resolved 邮件

该探测只证明 Retail UI 首页入口可达，不等同于完整下单链路或数据库恢复验证。

### 4. Kubernetes 对象状态

kube-state-metrics v2.20.0 只开放 Stage 4 当前需要的对象状态：

- Node
- Pod
- Deployment
- StatefulSet

已验证：

- 3/3 Node Ready
- Retail Deployment desired / available 指标
- Retail StatefulSet desired / ready 指标
- Pod phase / readiness 指标

当前没有 node-exporter，因此 Stage 4 不宣称具备节点 CPU、内存、磁盘等连续基础设施时序指标。

### 5. 可行动告警

最终 4 条规则：

- `RetailUIProbeFailed`
- `MonitoringTargetDown`
- `KubernetesNodeNotReady`
- `ArgoApplicationUnhealthy`

所有规则均：

- 通过 `promtool check rules`
- 具备时序行为测试
- 在真实 Prometheus 中成功加载
- 最终状态 `health=ok`
- 最终状态 `inactive`

规则评估失败计数在验收时为 0。

### 6. 诊断查询

Stage 4 保存四组诊断 PromQL：

1. 业务可用性
2. GitOps 状态
3. Node / Workload 状态
4. 监控系统自身

目标是支持“从告警到定位”，而不是为堆技术栈引入 Grafana、日志平台或 tracing。

## 真实告警与恢复证据

### Retail UI 指标驱动告警

一次受控判据演练已验证：

`probe_success 1 → 0 → 1`

并完成：

`pending → firing → resolved`

Alertmanager 已实际收到触发和恢复邮件。

### Argo CD 自然异常

2026-09-26 自然观察期间，Retail Application 短暂出现：

- Sync：`Unknown`
- Health：`Healthy`
- `ArgoApplicationUnhealthy`：pending

同期 repo-server 日志出现：

- `failed to list refs`
- GitHub `info/refs` 返回 EOF

观测失败窗口约为：

`06:34:57Z – 06:39:32Z`

随后：

- repo-server `GenerateManifest` 多次恢复 OK
- Retail 恢复到 `Synced / Healthy`
- 最终 conditions 为空

该异常未持续越过告警的 5 分钟 firing 阈值，因此没有观察到该规则进入 firing。Prometheus 的 `for` 语义就是要求条件持续满足指定时长后才从 pending 转为 firing。

这次事件与 Incident #003 所记录的间歇 GitHub 仓库访问问题属于同一类控制面症状。现有证据仍不足以证明唯一外部根因。

## S4-E 自然观察

墙钟观察窗口超过 24 小时。

### 已确认

- 可观测样本中的 Retail UI `probe_success` 最小值为 1
- 查询窗口内未观察到 firing alert
- 3 个 Node 最终均 Ready=1
- 最终 Retail：Synced / Healthy
- 最终 observability：Synced / Healthy
- 最终 8 个 target：全部 up=1
- 最终 4 条 Stage 4 告警：全部 ok / inactive

### 采样连续性限制

过去 24h 查询中：

- Prometheus `process_start_time_seconds` 发生 2 次变化
- 多数有数据的小时约 120 个样本，符合 30s scrape interval
- 至少一个退化小时只有 27 个样本
- 另一个小时为 71 个样本
- 至少存在一个多小时区间完全没有返回 hourly point
- 单 target 在 24h 窗口中总样本数约 817–818

因此，本阶段只能陈述：

> 观察墙钟窗口超过 24h，但 Prometheus 历史采样并非连续覆盖完整 24h。

不能据此声称：

- 24h 连续无故障
- 99.9% 可用性
- 完整 SLO 达标

采样空窗的具体原因没有由当前证据唯一确定，因此记录为已知限制，不做无依据归因。

## 最终资源快照

2026-09-27 16:36 CST：

| Node | Working memory | Available memory |
| --- | ---: | ---: |
| k8s-master | 1519 MiB | 2106 MiB |
| k8s-worker1 | 2325 MiB | 1300 MiB |
| k8s-worker2 | 1085 MiB | 2540 MiB |

Observability 组件 working set：

| Component | Node | Working memory |
| --- | --- | ---: |
| Blackbox Exporter | worker1 | 17 MiB |
| Alertmanager | worker1 | 25 MiB |
| kube-state-metrics | worker1 | 18 MiB |
| Prometheus | worker2 | 147 MiB |

当前资源快照未显示新增监控组件造成明显内存压力。

## 最终状态

2026-09-27 16:36 CST：

Retail：

- revision：`65fbff017c8ed41540678808282b43f6f06d8775`
- Synced
- Healthy

Observability：

- revision：`65fbff017c8ed41540678808282b43f6f06d8775`
- Synced
- Healthy

Prometheus targets：

- 8/8 up

Alert rules：

- 4/4 health=ok
- 4/4 inactive

## Stage 4 已知边界

1. Prometheus 单副本，不具备监控高可用。
2. Prometheus 使用 local-path-retain，本地节点存储不是跨节点复制。
3. 集群内监控无法在整个实验室或宿主机全部失效时独立通知。
4. Retail UI Blackbox 探测只覆盖首页入口，不覆盖完整交易链路。
5. 当前没有 node-exporter，不具备节点 CPU/内存/磁盘的连续指标面。
6. Alertmanager 自身状态仍不是高可用部署。
7. GitHub repo-server 外部访问仍存在间歇抖动历史。
8. S4-E 24h 墙钟观察存在 Prometheus 历史采样空窗，不声称连续 24h SLO。

这些限制均不阻塞进入 Stage 5，因为 Stage 4 的目标是建立可验证的最小观测与告警闭环，而不是一次性构建生产级全栈监控平台。

## 主要证据

- [Prometheus 持久化验收](stage4-prometheus-persistence.md)
- [监控组件自身抓取](stage4-observability-self-scrape.md)
- [kube-state-metrics 验收](stage4-kube-state-metrics.md)
- [可行动告警验收](stage4-actionable-alerts.md)
- [诊断 PromQL](stage4-diagnostic-queries.md)
- [Alertmanager 邮件通知](stage4-email-notifications.md)
- [指标驱动告警演练](stage4-metric-driven-alert-drill.md)
- [Retail UI 探测](stage4-ui-nodeport-probe.md)
- [平台告警 Runbook](../runbooks/stage4-platform-alerts.md)
- [Retail UI 告警 Runbook](../runbooks/retail-ui-probe-alert.md)
- [Incident #003](../incidents/003-argocd-repo-server-github-timeout/README.md)

## 下一阶段

Stage 5：Backup / Restore。

重点转向 Retail 有状态数据，优先建立：

- 备份对象与恢复目标
- 可重复备份流程
- 隔离恢复验证
- RPO / RTO 的实际测量
- 数据完整性验证
- 恢复 Runbook 与证据

Stage 5 不应依靠 Stage 4 的首页 HTTP 200 作为数据恢复成功标准。
