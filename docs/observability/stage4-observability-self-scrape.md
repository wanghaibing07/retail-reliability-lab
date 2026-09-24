# Stage 4：监控组件自监控验收（2026-09-24）

时区：北京时间 UTC+08:00。以下运行态来自用户在实验集群提供的终端结果。

## 变更

PR #37 为 Prometheus 增加两个直接 scrape job：

- `blackbox-exporter` → `blackbox-exporter.observability.svc.cluster.local:9115/metrics`
- `alertmanager` → `alertmanager.observability.svc.cluster.local:9093/metrics`

目的不是新增告警，而是把“业务探测失败”和“探测/通知组件自身不可用”区分开。

## 运行态验收

2026-09-24 17:42 CST：

- observability Application revision：`91b4959490621f3082ff6896a62a944a78285e87`
- Argo CD：Synced / Healthy
- 7 个配置的 scrape target 全部 `up=1`
- 新增 `blackbox-exporter=1`
- 新增 `alertmanager=1`
- 原有 Prometheus、Retail UI NodePort、Argo CD application-controller/server/repo-server 均保持 `up=1`

Blackbox Exporter 已确认抓到真实自身指标，包括：

- `blackbox_exporter_build_info`
- `blackbox_exporter_config_last_reload_successful`
- `blackbox_exporter_config_last_reload_success_timestamp_seconds`
- Go runtime/process metrics
- config reload success = 1

Alertmanager 已确认抓到真实自身指标，包括：

- `alertmanager_build_info`
- `alertmanager_alerts`
- `alertmanager_alerts_received_total`
- `alertmanager_cluster_members`
- `alertmanager_cluster_health_score`
- cluster/message metrics

## 结论

S4-C2 完成。两个组件不只是 HTTP 可达，而是 Prometheus 已采集到其组件原生指标。按最小充分验证原则，不再为本小项额外注入组件故障。下一步进入 S4-C3：精简 kube-state-metrics，对 Node、Pod、Deployment、StatefulSet 对象状态建立指标视角。
