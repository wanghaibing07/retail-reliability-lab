# Stage 4 第一批：Prometheus 抓取基线

本批只建立最小指标采集路径：Prometheus 自身、Argo CD application-controller、Argo CD server。它尚不包含 UI 外部探测、repo-server Git 失败、节点/Pod 状态、告警、通知或仪表盘；不能标记 Stage 4 完成。

## 依据与资源边界

2026-09-23 18:52–18:54 CST，用户从实验集群提供的命令摘要显示：Git/Argo revision 均为 `861e490193356c347163c0d8b712d78350bb2d94`，三节点 Ready，Retail 11/11 Ready。节点 working/available 内存分别为 master 1829/1796 MiB、worker1 2521/1104 MiB、worker2 1862/1763 MiB。单次样本不能代表峰值；内存 requests 也不能当成实际使用量。

第一批 Prometheus 固定在 worker2，申请 256 MiB、上限 768 MiB，临时 `emptyDir` 限 2 GiB，保留时间 24 小时。初次运行要对照 worker2 的实际内存和重启情况，不将该设定视为容量已验收。临时存储在 Pod 被替换时丢失；后续如需跨重启保留数据，再单独设计 PVC 与保留期。应用 Service 仅为 ClusterIP，通过 `kubectl port-forward` 访问，不公开监控界面。

## 镜像预置 gate

本项目的 containerd 运行时仅从内部 Registry 路由拉镜像，集群目前没有 Prometheus 镜像。固定源镜像为 `quay.io/prometheus/prometheus:v3.13.3`，内部目标路径为 `192.168.88.3:5000/prometheus/prometheus:v3.13.3`。镜像标签非内容摘要；推送后记录源/目标 digest，并在 worker2 冷拉验证。以下 pull 使用实验室现有 Windows 代理，若失败应停在镜像准备阶段，不要启动 Application：

```bash
sudo env HTTPS_PROXY=http://192.168.88.1:7890 \
  HTTP_PROXY=http://192.168.88.1:7890 \
  ctr -n k8s.io images pull --platform linux/amd64 \
  quay.io/prometheus/prometheus:v3.13.3

bash infra/registry/seed-observability.sh
```

然后在 **worker2** 上执行 `sudo crictl pull quay.io/prometheus/prometheus:v3.13.3`，核对 `sudo crictl inspecti quay.io/prometheus/prometheus:v3.13.3` 的 digest 和平台。源镜像引用保持不变，由现有 containerd mirror 路由到内部 Registry。不要在 Git 中提交代理凭据或 Registry 证书。

## 交付与验收 gate

1. feature branch 的 required `validate` 通过；检查 `kubectl kustomize infra/observability/prometheus` 输出及镜像版本。PR 合并后，在 master 的 `/root/retail-reliability-lab` 中通过现有代理执行 `sudo -n git -C /root/retail-reliability-lab -c http.proxy=http://192.168.88.1:7890 pull --ff-only`，核对本地 HEAD 与远端 main。
2. 仅在镜像冷拉成功后，用新 admin.conf 启动 Application：

   ```bash
   sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf \
     kubectl apply -f infra/argocd/observability-application.yaml
   ```

3. 查询 Application 的 sync/health/revision；确认 Prometheus 在 worker2 Ready、镜像未走公网、Service 有 Ready Endpoint。
4. 在 master 运行 `sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl -n observability port-forward svc/prometheus 9090:9090`，在另一终端访问 `http://127.0.0.1:9090/api/v1/query?query=up`。`prometheus`、`argocd-application-controller`、`argocd-server` 三个 job 的 `up` 均应为 1。还应查询一条确实存在的 Argo 应用状态指标，不能只凭 `/targets` 展示判断数据有效。
5. 观察 Prometheus Pod 重启/事件、worker2 的 Summary API 内存可用值与 2 GiB 临时数据实际使用量；若 Pod OOM、持续重启或 worker2 可用内存低于 512 MiB，停止扩展并先排查/回滚。本阈值只是这次实验的停止条件，不是正式告警阈值。

repo-server 暴露 8084 容器端口，但当前没有对应 metrics Service；后续需要明确 Service selector 或 Pod 发现方式，验证 Git 请求指标后再纳入监控。UI 的 HTTP 200 探测也只代表首页可达，不能替代下单事务或数据恢复验证。

如需中止本批，先暂停 `observability` Application 自动同步，再删除该 Application 和由本批清单管理的资源；`emptyDir` 内指标将丢失。不要触碰 `retail`、`argocd`、Registry 的有状态资源。
