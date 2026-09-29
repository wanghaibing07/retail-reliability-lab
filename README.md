# Retail Reliability Lab

基于 AWS Retail Store Sample App v1.6.2 的 Kubernetes 可靠性工程实验项目。

项目重点不是单纯“把应用跑起来”，而是逐步验证：

- 应用能否稳定、可重复部署
- 代码和 Kubernetes 清单变更能否自动检查
- Git 能否成为集群期望状态来源
- 故障能否被发现、定位和恢复
- 有状态数据能否完成可验证的备份与恢复

## 当前进度

| Stage | 内容 | 状态 |
| --- | --- | --- |
| Stage 0 | Baseline + Incident #001 | ✅ 完成 |
| Stage 1 | Reproducible Deploy | ✅ 完成 |
| Stage 2 | CI Validation | ✅ 完成 |
| Stage 3 | Argo CD / GitOps | ✅ 完成 |
| Stage 4 | Observability | ✅ 完成 |
| Stage 5 | Backup / Restore | ✅ 完成 |
| Stage 6 | Release Failure & Recovery | ✅ 完成 |
| Stage 7 | Performance / Capacity | ⏳ Planned |
| Stage 8 | Portfolio / Interview Packaging | ⏳ Planned |

## 已完成能力

### 1. Kubernetes 业务基线

固定使用 AWS Retail Store Sample App `v1.6.2`，部署包含：

- Cart
- Catalog
- Checkout
- Orders
- UI
- MySQL
- PostgreSQL
- RabbitMQ
- Redis
- DynamoDB Local

### 2. Incident #001：镜像拉取异常

在当前 VMware/NAT 实验环境中，并发镜像拉取出现过超时和连接异常。

完成了：

- DNS、HTTPS、Registry 连通性排查
- 单流与并发镜像拉取对比
- containerd 行为分析
- 镜像串行预拉取
- 故障恢复验证

最终将镜像获取从业务部署关键路径中拆离。

### 3. 可重复部署

实现以下脚本：

```text
scripts/
├── prepull-images.sh
├── deploy.sh
├── verify.sh
└── destroy.sh
```

部署流程：

```text
Pre-pull Images
      ↓
Create Namespace
      ↓
Apply Manifest
      ↓
Workload Verification
      ↓
Service Endpoint Verification
      ↓
Business HTTP Verification
```

完成两次完整重建：

```text
destroy
   ↓
deploy
   ↓
verify
```

验证结果：

| Test | Result | Duration | Manual Intervention |
| --- | --- | ---: | ---: |
| Rebuild #1 | PASS | 4m29.672s | 0 |
| Rebuild #2 | PASS | 3m47.237s | 0 |

两次测试最终业务 HTTP 均返回 `200`。

### 4. 分层健康验证

`verify.sh` 不只检查 Pod 是否运行，而是进行三层验证：

```text
Workload Ready
      ↓
Service Ready Endpoint
      ↓
Business HTTP 200
```

核心原则：

```text
Pod Running
≠ Pod Ready
≠ Service Available
≠ Business Healthy
```

### 5. GitHub Actions CI

当前 CI 在 Push 和 Pull Request 时自动执行：

- Bash syntax check
- ShellCheck
- Kubernetes Manifest Schema Validation
- 禁止使用 `latest` 镜像标签

CI 曾真实发现 `SC2029` 问题，并通过：

```text
CI Failure
    ↓
fix/ci-shellcheck
    ↓
Pull Request
    ↓
CI Validation
    ↓
Merge into main
```

完成修复。

当前 `main` 分支 CI 已验证通过。

## 项目结构

```text
retail-reliability-lab/
├── .github/
│   └── workflows/
│       └── ci.yml
├── docs/
│   ├── incidents/
│   ├── runbooks/
│   ├── decisions/
│   └── gitops/
├── evidence/
├── infra/
│   ├── vendor/
│   ├── apps/
│   │   └── retail/
│   └── argocd/
├── scripts/
│   ├── prepull-images.sh
│   ├── deploy.sh
│   ├── verify.sh
│   ├── backup-orders.sh
│   ├── restore-orders.sh
│   └── destroy.sh
└── README.md
```

## Stage 3：Argo CD / GitOps

Stage 3 已完成 GitOps 交付闭环：

- `infra/apps/retail` 是 Retail 唯一 desired-state 入口
- CI、Argo CD、`deploy.sh`、`prepull-images.sh` 统一使用该入口
- Argo CD 平台配置已通过 Git/Kustomize 声明化管理
- Resource Tracking 显式配置为 annotation
- GitHub `main` 已启用 branch protection 和 required CI
- Manual Sync 已验证
- Auto Sync 已验证
- Self Heal 已验证
- Auto Prune 已通过一次性 ConfigMap 实验验证
- MySQL、PostgreSQL、RabbitMQ StatefulSet 使用 `Prune=confirm`
- `destroy.sh` 已具备 GitOps-aware、dry-run 和 fail-closed 防护
- `verify.sh` 从 Git expected state 出发验证 workload、Service、EndpointSlice 和 HTTP

当前自动同步策略：

```yaml
automated:
  enabled: true
  prune: true
  selfHeal: true
  allowEmpty: false
```

Stage 3 最终验证确认：

```text
Git main
→ protected PR / required CI
→ Argo reconciliation
→ Synced / Healthy
→ workload ready
→ Service ready endpoints
→ business HTTP 200
```

同时确认：

- Auto Prune probe 已删除
- 3 个 StatefulSet 保持 `Prune=confirm`
- Argo CD platform 与 Git desired state 无 drift
- Incident #003 的 retry mitigation 已声明化

Incident #003 在 Kubernetes 1.36.4 重建后再次复现并完成更深层网络排查。
当前证据将故障边界定位为不稳定的 GitHub 直连外部路径，无法继续证明到唯一上游组件。
Retail repository 已通过 Argo CD repository-specific proxy 获得稳定访问；该方案作为实验室环境 mitigation，不宣称修复了原始直连路径。

详细记录：

- [Stage 3 GitOps](docs/gitops/stage3-gitops.md)
- [Incidents](docs/incidents/)
- [Runbooks](docs/runbooks/)
- [Decisions](docs/decisions/)

## 当前实验室基线

2026-09-23 完成一次完整 Kubernetes 重建恢复验证：

```text
Kubernetes 1.36.4
containerd 2.3.4
3/3 Nodes Ready
Argo CD v3.5.2
Retail Synced / Healthy
verify.sh PASS
business HTTP 200
```

这次验证从新的 control plane 开始，依次恢复网络、Registry、Storage、Argo CD 和 Retail GitOps desired state。

详细决策记录：

* [Kubernetes 1.36.4 Rebuild](docs/decisions/002-kubernetes-136-rebuild.md)

## Stage 4：可观测性（已完成）

Stage 4 已完成最小可观测与告警闭环：

- Prometheus v3.13.3 持久化到 `local-path-retain` PVC，48h / 3GB retention
- Blackbox Exporter 跨节点探测 Retail UI NodePort
- Alertmanager 已真实验证 firing 与 resolved 邮件
- kube-state-metrics 采集 Node、Pod、Deployment、StatefulSet 对象状态
- Prometheus 当前监控 8 个 target
- 4 条可行动告警：Retail UI、监控/GitOps target、Node Ready、Argo Application 状态
- 告警规则具备 promtool 语法检查与时序行为测试
- 保存四组诊断 PromQL：业务、GitOps、Node/Workload、监控自身
- Prometheus PVC 已验证跨 Pod 替换保留历史样本
- 最终 Retail / observability 均为 Synced / Healthy，8/8 targets up，4/4 alert rules health=ok / inactive

自然观察期间真实捕获一次 repo-server GitHub `info/refs` EOF：
Retail 短暂进入 `Sync=Unknown`，`ArgoApplicationUnhealthy` 进入 pending，
随后仓库访问恢复且 Application 自动回到 Synced / Healthy。
该异常未持续越过 5 分钟 firing 阈值。

S4-E 的墙钟观察窗口超过 24h，但 Prometheus 在该窗口内重启过两次并存在历史采样空窗，
因此项目**不声称连续 24h 无故障、99.9% 可用性或完整 SLO 达标**。
这作为已知观测限制保留，而不是用缺失样本推断系统健康。

Stage 4 仍明确保持以下边界：

- Prometheus / Alertmanager 均非高可用部署
- local-path-retain 不是跨节点复制存储
- 集群内监控无法覆盖整个实验室完全停机
- Retail UI HTTP 200 只验证首页入口，不代表完整交易链路
- 当前未部署 node-exporter，不宣称具备节点 CPU/内存/磁盘连续时序指标
- GitHub repo-server 外部访问仍存在间歇抖动历史

完整封板证据：

- [Stage 4 Closeout](docs/observability/stage4-closeout.md)
- [Prometheus 持久化](docs/observability/stage4-prometheus-persistence.md)
- [kube-state-metrics](docs/observability/stage4-kube-state-metrics.md)
- [可行动告警](docs/observability/stage4-actionable-alerts.md)
- [诊断 PromQL](docs/observability/stage4-diagnostic-queries.md)
- [邮件通知](docs/observability/stage4-email-notifications.md)
- [指标驱动告警演练](docs/observability/stage4-metric-driven-alert-drill.md)

Stage 4 已封板，后续恢复能力由 Stage 5 验证。


## Stage 5：Backup / Restore（已完成）

Stage 5 聚焦 Orders PostgreSQL，完成从临时 `emptyDir` 到 retained PVC 的可验证迁移与恢复闭环：

- 使用 `pg_dump -Fc` 生成 PostgreSQL 逻辑备份
- 备份先写 `.partial`，通过非空、`pg_restore --list`、SHA256 后才发布正式归档
- 备份副本离开原数据库 VM：`k8s-worker1 → k8s-master`
- 在 `k8s-worker2` 隔离 PostgreSQL 中真实执行 `pg_restore`
- 数据库层与 Orders 1.6.2 应用层均验证恢复 marker
- 在维护窗口冻结 Checkout / Orders 写入后创建 final backup
- 生产 `orders-postgresql` 从 `emptyDir` 迁移到 `orders-postgresql-data`
- PVC：4Gi / RWO / `local-path-retain` / PV reclaimPolicy=Retain
- final backup 恢复到生产 PVC 后，由正式 StatefulSet 接管
- 迁移前订单与迁移后新订单均通过 PostgreSQL 和 Orders API 验证
- 主动删除并重建 `orders-postgresql-0`，两个订单均保留

关键实测：

```text
isolated restore -> application validation : 81.285s
production PVC pg_restore                 : 0.365s
final backup                              : 6s
```

本次受控实验中未观察到已确认 Orders 记录丢失。

Stage 5 只证明：

> 已验证 Orders PostgreSQL 数据库的备份、持久化和隔离恢复能力。

不宣称：

- 整个 Retail 的分布式一致性灾备
- worker2 节点丢失后的跨节点存储自动故障转移
- 异地 / off-site backup
- 持续备份或保证 RPO=0
- 保证生产 RTO

完整记录：

- [Stage 5 Closeout](docs/backup/stage5-closeout.md)
- [Orders PostgreSQL Backup](docs/backup/orders-postgresql.md)
- [Orders PostgreSQL Restore Runbook](docs/runbooks/orders-postgresql-restore.md)
- [Orders PostgreSQL PVC Migration Runbook](docs/runbooks/orders-postgresql-pvc-migration.md)
- [Stage 5 Evidence](docs/evidence/stage5/)

下一阶段：Stage 6 Release Failure & Recovery。

## Stage 6：Release Failure & Recovery（已完成）

Stage 6 已完成一次受控 UI 发布失败与 GitOps 恢复闭环。

长期保留的 release safety：

- UI `replicas=2`
- `progressDeadlineSeconds=120`
- `maxUnavailable=0`
- `maxSurge=1`
- `KubernetesDeploymentRolloutStalled` 发布停滞告警

受控实验故意将 UI readiness path 从：

```text
/actuator/health/readiness
```

改为不存在的路径，使一个通过静态 CI 的合法 Kubernetes 变更在运行时产生真实 rollout failure。

实测链路：

```text
PR / CI PASS
      ↓
Git merge
      ↓
Argo CD reconciliation
      ↓
new UI Pod Running / NotReady
      ↓
bad endpoint ready=false
      ↓
old 2 healthy replicas continue serving
      ↓
ProgressDeadlineExceeded
      ↓
KubernetesDeploymentRolloutStalled firing
      ↓
Git revert PR / CI PASS
      ↓
Argo CD reconciliation
      ↓
UI Healthy
      ↓
alert cleared
      ↓
verify.sh PASS
```

关键观测：

- 坏版本：`ba058deadec602ae0392ab8a42cb2c72fa13061d`
- 恢复版本：`9cae7211894947f6a780fcac9678121255e675a0`
- Argo 开始同步坏版本后约 `2m02s` 观察到 `ProgressDeadlineExceeded`
- 失败期间旧 UI replicas 保持 Ready
- 采集到的用户入口请求持续返回 HTTP 200
- recovery merge 后 `41s` 观察到 Argo 恢复 Healthy
- 最终 `verify.sh` PASS

正式 recovery 没有使用 `kubectl rollout undo`、live patch 或手工修改线上对象，而是：

```text
bad Git merge
→ git revert
→ recovery PR
→ CI
→ merge
→ Argo CD reconciliation
```

因此 Stage 6 验证的是：

> 在当前 Kubernetes + Argo CD GitOps 环境中，一次受控 UI 发布失败能够被检测、限制影响范围，并通过可审计的 Git desired-state 恢复。

本阶段不宣称：

- 已实现自动 rollback
- 已实现 Canary / Blue-Green
- 所有业务语义错误都能被 readiness 检测
- 已证明生产零停机
- 所有 Retail 服务都具备相同 release safety

完整记录：

- [Stage 6 Closeout](docs/releases/stage6-closeout.md)
- [Release Failure Recovery Runbook](docs/runbooks/release-failure-recovery.md)
- [Stage 6 Evidence](docs/evidence/stage6/readiness-failure-001/)

下一阶段：Stage 7 Performance / Capacity。

## 项目边界

这是本地 Kubernetes 实验环境，不宣称为生产级高可用架构。

当前重点是验证：

- 自动化交付
- GitOps
- 可观测性
- 故障恢复
- 数据恢复

项目不会为了堆叠技术关键词而无目的加入大量组件。
