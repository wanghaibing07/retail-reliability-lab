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
| Stage 4 | Observability | ⏳ Planned |
| Stage 5 | Backup / Restore | ⏳ Planned |
| Stage 6 | Release Failure & Recovery | ⏳ Planned |
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

Incident #003 的底层 VMware guest outbound 网络问题仍未定位到唯一组件，
因此只声明为“部分缓解”，不宣称根因已经修复。

详细记录：

- [Stage 3 GitOps](docs/gitops/stage3-gitops.md)
- [Incidents](docs/incidents/)
- [Runbooks](docs/runbooks/)
- [Decisions](docs/decisions/)

## 项目边界

这是本地 Kubernetes 实验环境，不宣称为生产级高可用架构。

当前重点是验证：

- 自动化交付
- GitOps
- 可观测性
- 故障恢复
- 数据恢复

项目不会为了堆叠技术关键词而无目的加入大量组件。
