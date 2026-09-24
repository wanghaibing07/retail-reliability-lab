# Stage 4：Prometheus TSDB 持久化验收（2026-09-24）

时区：北京时间 UTC+08:00。以下运行态来自用户在实验集群提供的终端结果。

## 变更

PR #36 将 Prometheus 的 `/prometheus` 从 2Gi `emptyDir` 切换为 `prometheus-data` PVC：

- StorageClass：`local-path-retain`
- PVC 请求：4Gi
- AccessMode：ReadWriteOnce
- Argo CD：PVC 使用 `Prune=confirm`
- TSDB：`--storage.tsdb.retention.time=48h`
- TSDB：`--storage.tsdb.retention.size=3GB`
- Prometheus 仍为单副本、`Recreate`，固定在 `k8s-worker2`

首次从 `emptyDir` 切换到 PVC 时不迁移旧 TSDB。此前 Stage 4 告警演练证据已保存在 Git 文档中。

## 部署验收

2026-09-24 17:26 CST：

- observability Application revision：`660929f63cc0fb6b6edd33f8cdc04a6532532f9d`
- Argo CD：Synced / Healthy
- PVC `prometheus-data`：Bound，4Gi，RWO，`local-path-retain`
- PV：`pvc-ae1b9610-f766-4396-9fd6-608961449bc1`
- Prometheus：1/1 Ready，Running，0 restarts，node=`k8s-worker2`
- Deployment 的 `data` volume 已指向 `prometheus-data`
- retention 参数为 48h / 3GB，TSDB path 为 `/prometheus`

## Pod 替换后的历史样本验证

2026-09-24 17:32 CST 执行一次受控 Prometheus Pod 替换：

- before pod：`prometheus-6c99699c97-mkw4r`
- before UID：`41f41c11-c76b-4df0-90bd-8346cee530a0`
- after pod：`prometheus-6c99699c97-j9w7h`
- after UID：`d6ddea3c-279f-41f6-822d-3e872ada334d`
- rollout：successfully rolled out
- 固定 checkpoint timestamp：`1790242380.485`
- 替换前 `up{job="prometheus"}` 值：`1`
- 替换后按同一 timestamp 查询得到：timestamp=`1790242380.485`、value=`1`
- 结果：`PROMETHEUS_TSDB_PERSISTENCE=PASS`

替换后当前已有五个 scrape job 的 `up` 均为 1：Prometheus、Argo CD application-controller/server/repo-server、Retail UI NodePort probe。

## 结论

S4-C1 完成。PVC 已真实跨 Prometheus Pod 替换保留历史样本，不再重复删除 Pod 做同类验证。后续进入 S4-C2：增加 Blackbox Exporter 和 Alertmanager 自身 `/metrics` 抓取；该步骤不提前增加新的告警规则。
