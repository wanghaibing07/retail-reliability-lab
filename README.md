# Retail Reliability Lab

这是我在三台 VMware 虚拟机上做的 Kubernetes 运维实验。应用使用 **AWS Retail Store Sample App v1.6.2**，业务代码来自 AWS；我维护部署配置、运维脚本和实验记录。

## 项目概况

项目从镜像拉取异常排查开始，随后整理了部署和检查脚本，接入 GitHub Actions、Argo CD 与监控，再做订单数据库恢复、发布失败和性能测试。各阶段的配置、操作步骤和结果保存在仓库中。

几项已经完成的验证：

| 记录 | 主要结果 |
| --- | --- |
| [自动部署与配置同步](docs/gitops/stage3-gitops.md) | 修改先自动检查再部署；手工把 UI 改为一个副本后，Argo CD 恢复为 Git 中的两个 |
| [告警通知](docs/observability/stage4-metric-driven-alert-drill.md) | 临时改变探测成功判据，实际收到触发和恢复邮件；演练期间业务入口仍返回 200 |
| [订单数据库恢复](docs/backup/stage5-closeout.md) | 隔离恢复后应用能读回订单；迁移至持久存储并重建 Pod 后，新旧订单仍在 |
| [发布失败演练](docs/releases/stage6-closeout.md) | 新 UI 实例无法就绪时，旧实例继续服务；撤销 Git 配置后恢复 |
| [性能测试](docs/performance/stage7-closeout.md) | 只读浏览负载下，30 RPS 持续 300 秒已验证健康；45 RPS 多轮阶段性退化，后段恢复，最大容量尚未确定 |

[项目概况与术语说明](docs/portfolio/plain-language-guide.md)按实际过程介绍这些记录；[架构图](docs/portfolio/architecture.md)说明服务之间的关系。

## 当前进度

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| Stage 0 | 业务基线与第一次故障排查 | ✅ 完成 |
| Stage 1 | 可重复部署 | ✅ 完成 |
| Stage 2 | 自动检查与质量门禁 | ✅ 完成 |
| Stage 3 | Git 驱动部署与自动纠偏 | ✅ 完成 |
| Stage 4 | 监控与告警 | ✅ 完成 |
| Stage 5 | 备份与恢复 | ✅ 完成 |
| Stage 6 | 发布失败与恢复 | ✅ 完成 |
| Stage 7 | 性能与容量验证 | ✅ 完成 |
| Stage 8 | 作品集与面试材料 | ✅ 完成 |

### 相关文档

- [中文架构图与 60 秒项目讲解](docs/portfolio/architecture.md)
- [3～5 条简历项目描述](docs/portfolio/resume-bullets.md)
- [3 分钟 / 10 分钟讲解](docs/portfolio/interview-guide.md)
- [五个工程与排障故事](docs/portfolio/incident-stories.md)
- [项目面试题库：先回答，再看证据](docs/portfolio/interview-question-bank.md)
- [统一声明边界：可以说什么、证据在哪里](docs/portfolio/claim-boundaries.md)
- [stage7-v0.8 GitHub Release](https://github.com/wanghaibing07/retail-reliability-lab/releases/tag/stage7-v0.8)
- [Stage 8 验收与材料使用顺序](docs/portfolio/stage8-closeout.md)
- [Stage 7 封板报告](docs/performance/stage7-closeout.md)
- [Stage 7 证据索引](evidence/stage7/README.md)
- [Stage 6 发布恢复报告](docs/releases/stage6-closeout.md)
- [Stage 5 数据恢复报告](docs/backup/stage5-closeout.md)
- [Stage 4 监控验收报告](docs/observability/stage4-closeout.md)
- [Stage 3 GitOps](docs/gitops/stage3-gitops.md)


## 已完成能力

下方按阶段保留历史验证记录；Healthy、target 数量及组件范围描述的是对应阶段的观测，不代表实验室当前在线状态。对外表达统一参照 [声明边界](docs/portfolio/claim-boundaries.md)。

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
- Stage 4 封板时 Prometheus 监控 8 个 target；Stage 7 另扩展了应用与容器指标
- 4 条可行动告警：Retail UI、监控/GitOps target、Node Ready、Argo Application 状态
- 告警规则具备 promtool 语法检查与时序行为测试
- 保存四组诊断 PromQL：业务、GitOps、Node/Workload、监控自身
- Prometheus PVC 已验证跨 Pod 替换保留历史样本
- Stage 4 最终快照：Retail / observability 均为 Synced / Healthy，8/8 targets up，4/4 alert rules health=ok / inactive

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
- Stage 4 未部署 node-exporter；后续历史采样与 Git 中的可重复部署范围需分别核对，不宣称节点指标连续、无空窗
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

## Stage 7 Performance / Capacity

容量实验按环境限制封板：30 RPS /300s 已验证健康；45RPS 可重复退化；39RPS 未有效资格确认。精确拐点和硬容量上限未确定。S7-F 无充分因果证据，因此不新增SUT优化。

- [Stage 7 封板报告](docs/performance/stage7-closeout.md)
- [Stage 7 证据索引](evidence/stage7/README.md)

文档与证据已收齐到上述索引；最终验收以 [PR #57](https://github.com/wanghaibing07/retail-reliability-lab/pull/57) 的实际合并提交、CI 和 `stage7-v0.8` annotated tag 为准。

## 项目边界

这是本地 Kubernetes 实验环境，不宣称为生产级高可用架构。

当前重点是验证：

- 自动化交付
- GitOps
- 可观测性
- 故障恢复
- 数据恢复

项目不会为了堆叠技术关键词而无目的加入大量组件。
