# RetailUIProbeFailed：定位和恢复

适用范围：从 worker1 的 Blackbox Exporter 探测 worker2 `:32065` 上的 Retail UI 首页。
告警持续条件为 2 分钟。单次 HTTP 200 只代表该入口的一次请求成功。

## 先判断故障在哪一段

在 k8s-master 执行以下只读命令。显式使用当前 kubeconfig；请求集群内 Service 时绕开宿主代理。

```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n argocd get application observability retail
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n observability get pods -o wide
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n retail get deployment ui
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n retail get endpointslices -l kubernetes.io/service-name=ui
curl --noproxy '*' -sS -o /dev/null -w '%{http_code}\n' --max-time 10 http://192.168.88.5:32065/
```

查询 Prometheus 中这个 job 的 `up`、`probe_success`、`probe_http_status_code`，并查看
`/api/v1/rules` 中 `RetailUIProbeFailed` 的 `health`、`state`、`lastError`。

| 结果 | 下一步 |
| --- | --- |
| `up=1, probe_success=0` | Blackbox 完成采集，但 HTTP 请求或成功判据失败；检查响应码、Blackbox 配置及目标连接。 |
| `up=0` | Prometheus 抓取 Blackbox 失败；检查 Blackbox Pod、Service、Endpoint 和网络。不能直接判定 UI 已停机。 |
| `up=1`，`probe_success` 缺失 | 查看 Blackbox `/probe` 响应、模块参数及该指标是否被导出。 |
| 整个 job 的 `up` 消失 | 先检查 Prometheus 当前配置、目标发现与最近 Git/Argo 变更。 |
| `up=1, probe_success=1` | 探测已恢复；核对同一告警是否退出 firing，再查邮件恢复通知。 |

若 UI 响应异常，再查 Ready 副本、Service EndpointSlice、UI 日志和依赖；
若只有判据或监控组件异常，按相应配置的 Git 提交恢复。保留实际观测、变更 SHA、
发现与恢复时间。自动同步期间通过 Git 恢复声明式配置，避免现场修复被 Argo 覆盖。

## 告警边界

规则按 `job,instance` 保留单目标标签：探测失败、抓取失败和探测指标缺失不会
因为 `absent` 的不同标签额外生成第二条告警。整条 job 的 `up` 消失时产生一个
不带 `instance` 的兜底告警。目前只有一个静态目标；将来增加多目标时，
若其中某个目标从服务发现中完全消失，仍需固定目标清单或另外设计缺失检测。

监控栈与业务均在单个实验集群内；全集群停机无法依靠这条集群内告警通知。
