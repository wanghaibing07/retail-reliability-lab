# Stage 4：Retail UI 跨节点 HTTP 探测

## 探测边界

2026-09-24 01:14 CST，从 master 访问 worker2 `http://192.168.88.5:32065/` 返回 HTTP 200。UI Service 当前将 80/TCP 转到容器端口 `http`，已分配 NodePort 32065；本变更把它明确写入 Git，以防 Service 重建后漂移。探针运行在 worker1，经 worker2 的 NodePort 访问 UI；这验证跨节点路径和首页 HTTP 200，不代表 VMware 外部用户可达，也不能代替结算事务验证。若 worker2 IP 变化，要同步更新探测目标。

Blackbox Exporter 使用 `quay.io/prometheus/blackbox-exporter:v0.28.0`，requests 10m/32Mi、limits 100m/128Mi，worker1 在 01:19 CST 可用内存 1332 MiB。`http_200` 模块仅接受 200，不跟随重定向；Prometheus 每 30 秒访问其 `/probe`，超时 15 秒。观察 `probe_success` 和 `probe_http_status_code`；`up` 只证明 Prometheus 能抓取探针接口，不表示 UI 健康。

## 镜像与上线 gate

实验室 containerd 使用内部 Registry 镜像路由。合并 PR 前，先在 master 通过既有代理拉取源镜像，执行 `infra/registry/seed-blackbox.sh` 的同等 seed 流程，将 linux/amd64 镜像推到 `192.168.88.3:5000/prometheus/blackbox-exporter:v0.28.0`；在 worker1 不带代理冷拉源引用，核对 Registry 访问记录和 digest。一旦拉取失败，保持 PR 未合入，不创建探针工作负载。不得提交代理凭据或 Registry 证书。

镜像确认后，CI `validate` 必须通过；核对 `kubectl kustomize infra/apps/retail` 的 UI Service NodePort 为 32065，以及 `kubectl kustomize infra/observability/prometheus` 包含黑盒探针 Deployment、Service、配置及新抓取任务。合并后核对两个 Argo Application 的 revision、sync、health，验证 blackbox 在 worker1 Ready、Prometheus Ready，查询 `up{job="retail-ui-nodeport"}`、`probe_success{job="retail-ui-nodeport"}`、`probe_http_status_code{job="retail-ui-nodeport"}` 和原有四个任务。期望抓取 up=1、probe_success=1、状态码 200；出现 up=1/probe_success=0 时排查目标端口和 HTTP 返回。再次采集 worker1 可用内存、探针重启数。

Prometheus 的配置变更会更换 Pod，其 `emptyDir` 历史数据随 Pod 消失。新 Pod 的重启数从零重新观察；这次采集结果只能覆盖工作负载更新后的窗口。
