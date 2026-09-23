# Stage 4：UI 探测告警规则

在现有 Prometheus 加载 `RetailUIProbeFailed`：当 `retail-ui-nodeport` 的业务探测返回失败、抓取失败或探测序列消失并持续 2 分钟时，规则转为 firing。正常时应在 `/api/v1/rules` 看到规则已加载、状态 inactive，且 `probe_success=1`、`up=1`。检查 `prometheus_rule_evaluation_failures_total` 无新增失败。

此批只生成 Prometheus 告警状态；尚未部署 Alertmanager，也没有通知接收方，**不能宣称已能主动通知值班人员**。暂不制造 Retail UI 停机来验证 firing；后续可在隔离环境做故障注入，并接入接收方后再验证通知链路。

修改 Prometheus ConfigMap 会更换 Pod；`emptyDir` 的旧指标历史随 Pod 更换而丢失。合入后检查新 Pod Ready、Application Synced / Healthy，读取一次 `/api/v1/rules` 和现有 UI 探测结果即可，异常时再展开排查。
