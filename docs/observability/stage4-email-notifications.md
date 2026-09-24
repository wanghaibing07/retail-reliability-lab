# Stage 4：通过邮件通知 UI 探测告警

## 部署边界

Prometheus 的 `RetailUIProbeFailed` 已在本地评估，本批添加单副本 Alertmanager（worker1，requests 20m/64Mi、limits 200m/256Mi），经集群内 Service `alertmanager:9093` 接收 Prometheus 的告警并转发邮件。Service 仅 ClusterIP；短期存储是 `emptyDir`，Pod 更换后 silence 等状态会丢失。单副本也不能覆盖 Alertmanager 自身或整个集群失效时的通知；不要宣称外部独立监控。

由于仓库公开，实际发件邮箱、收件邮箱和授权码**不写入 Git**。部署前在 `observability` 命名空间手动创建 `alertmanager-config` Secret，其中键 `alertmanager.yml` 为路由与 SMTP 配置，键 `smtp_password` 为授权码原文。Deployment 将这两个键作为只读文件挂载；请不要把 Secret YAML、授权码或 SMTP 登录日志贴到讨论中。Secret 不由 Argo CD 管理，重新建集群时必须重新注入。

以下模板适用于个人 `@163.com` 发件邮箱，仍须在本机填写实际发件与收件地址，并启用该邮箱的 SMTP 服务、生成客户端授权码。使用 `smtp.163.com:465` 和隐式 TLS；如果是网易企业邮箱，主机名与授权方式可能不同，不能套用此模板。不要关闭 TLS 来规避连接问题。

```yaml
global:
  smtp_smarthost: 'smtp.163.com:465'
  smtp_force_implicit_tls: true
  smtp_from: 'SENDER@163.com'
  smtp_auth_username: 'SENDER@163.com'
  smtp_auth_password_file: /etc/alertmanager/smtp_password
  smtp_require_tls: true
route:
  receiver: email
  group_by: [alertname]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
receivers:
  - name: email
    email_configs:
      - to: 'RECIPIENT@example.invalid'
        send_resolved: true
```

## 合并前与上线验收

先确认 worker1 到实际 SMTP 主机/端口可达，并在 master 拉取 `quay.io/prometheus/alertmanager:v0.33.1`、推到内部 Registry；在 worker1 去掉代理冷拉，核对镜像摘要和 Registry 日志。在本机准备私密配置与密码文件，如可用，先运行 `amtool check-config` 校验，再创建 Secret，确认 Secret 只存在于集群中。镜像和 Secret 未准备好时，保持 PR 为草稿，避免自动同步一个无法启动的 Deployment。

CI 检查新资源和脚本。合并后只需核对 Argo CD 状态、Alertmanager Ready、Prometheus `/api/v1/alertmanagers` 的 active 目标。通过经过约定的隔离测试告警验证触发与恢复邮件确实送达；失败时再检查通知错误指标；不停止 Retail UI，也不向真实告警通道反复注入故障。没有实际收到邮件前，本批只能称作“通知链路已配置”，不能称作已验收。

## 上线验收记录（2026-09-24，UTC+08:00）

- PR #30 合并提交：`696cd10b0e2375f2dfd0a1832bccab7b6498442c`；observability Application 与该提交一致，状态为 Synced / Healthy；Alertmanager Deployment 已完成 rollout。
- Alertmanager v0.33.1 的 linux/amd64 镜像已推入内部 Registry，索引摘要为 `sha256:805cd1ba019080871a809d0a8f06f66d0bc891dcda315991b18a13d0379d7de7`，与 worker1 已拉取镜像的 repo digest 一致。worker1 的一次拉取早于本轮明确记录的推送完成时间，当时 Registry 日志查询没有命中；无法据此排除更早的入库，也无法确认该次拉取的实际路径。
- Prometheus `/api/v1/alertmanagers` 列出 active 目标 `alertmanager.observability.svc.cluster.local:9093`。
- 独立测试告警 `Stage4MailPipelineTest` 通过 Alertmanager API 提交，收件箱收到触发邮件；向相同告警提交结束时间后返回 HTTP 200，收件箱收到标题含 `RESOLVED` 的恢复邮件。没有中断 Retail UI。
- 此测试证实 Alertmanager 的 SMTP 发件与恢复通知；实际 `RetailUIProbeFailed` 规则未人为触发。真实邮箱地址和授权码未写入仓库；重建集群时仍需手动重建 Secret。
