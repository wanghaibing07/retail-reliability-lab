# Retail Reliability Lab

基于 [AWS Retail Store Sample App v1.6.2](https://github.com/aws-containers/retail-store-sample-app) 构建的**三节点 Kubernetes 可靠性工程实验室**。围绕一套有状态、多服务的电商样例，完成从部署、持续交付、监控告警到数据恢复、故障发布和容量分析的工程实践。

业务程序采用 AWS 开源样例；我负责 Kubernetes 部署和配置、自动化脚本、GitOps/CI、监控告警、故障演练及实测证据整理。

## 核心成果

| 方向 | 做了什么 | 实测结果 |
|---|---|---|
| **自动化部署** | 将镜像准备、部署、分层验证和清理拆成脚本 | 两轮重建分别在 **4m29s**、**3m47s** 完成，均无人工干预，业务 HTTP 200 |
| **CI / GitOps** | 用 GitHub Actions 检查 Shell 与 Kubernetes 清单；Argo CD 自动同步、纠偏 | 手动将 UI 从两个副本改成一个后，Argo CD 恢复为 Git 中的两个副本 |
| **监控告警** | 接入 Prometheus、Blackbox、kube-state-metrics、Alertmanager | 通过受控探测判据，验证指标变化、规则触发、告警邮件及恢复通知的完整链路 |
| **备份恢复** | 为 Orders PostgreSQL 建立备份、隔离恢复和持久卷迁移流程 | 恢复数据可由应用读取；重建数据库 Pod 后，迁移前后订单均保留 |
| **发布保护** | 结合 readiness、滚动更新策略、发布停滞告警和 Git revert | 错误的新 UI Pod 无法接流量，旧实例继续提供服务；撤销变更后恢复 |
| **容量分析** | 使用 Artillery 固定浏览负载，结合请求、延迟、资源指标分析 | **30 RPS 持续 300 秒健康**；45 RPS 多轮出现阶段性退化，形成有边界的容量判断 |

[查看完整架构与服务依赖](docs/portfolio/architecture.md)

## 工程设计

```text
Git / Pull Request
       │
       ▼
GitHub Actions（ShellCheck / K8s 清单检查）
       │
       ▼
main → Argo CD → Kubernetes Retail 业务
                     │
              ┌──────┼──────────┐
              ▼      ▼          ▼
           探测/指标 数据库     发布状态
              │      │          │
              ▼      ▼          ▼
        告警与通知  备份恢复   Git revert
```

**为什么这样设计？** 将“代码检查通过”与“运行中业务健康”分开验证。CI 负责尽早发现配置和脚本问题；Argo CD 让变更和运行状态保持一致；监控与 HTTP 验证负责发现服务真实异常；备份与恢复流程用实际订单数据检验结果。

## 重点案例

### 1. GitOps 配置自愈与真实排障

将 Retail 应用配置纳入 Git 管理，实现 Argo CD 自动同步、自愈及受控 Prune 演练。曾遇到 Argo CD repo-server 访问 GitHub 间歇超时；经过网络链路排查，通过仓库级代理与重试缓解，使实验环境的仓库访问恢复稳定。

[GitOps 记录](docs/gitops/stage3-gitops.md) · [Incident #003](docs/incidents/003-argocd-repo-server-github-timeout/README.md)

### 2. 让告警真正跑通，而不只是发测试邮件

通过改变 Blackbox 对 HTTP 状态码的接受条件，让正常返回 200 的页面触发探测失败。Prometheus 规则进入 firing、Alertmanager 发出邮件；恢复条件后又收到 resolved 通知。这个演练证明了**探测 → 指标 → 规则 → 通知 → 恢复**的实际链路。

[告警演练](docs/observability/stage4-metric-driven-alert-drill.md) · [监控配置](infra/observability/prometheus/)

### 3. 从备份文件走到实际订单恢复

对 Orders PostgreSQL 执行逻辑备份，先在隔离环境验证恢复与应用读数，再迁移到带 Retain 策略的 PVC。恢复后重新创建数据库 Pod，验证旧订单和新订单仍可读取。

[数据恢复证据](docs/backup/stage5-closeout.md) · [恢复脚本](scripts/restore-orders.sh)

### 4. 一次受控的失败发布与 Git 恢复

故意修改 UI readiness 路径，使通过静态检查的新版本在运行时无法就绪。坏实例未进入可用后端，已有两个健康副本保持服务；发布停滞触发告警。通过 Git revert 和 Argo CD 同步恢复业务，最终验证通过。

[发布失败与恢复](docs/releases/stage6-closeout.md) · [故障证据](docs/evidence/stage6/readiness-failure-001/)

### 5. 用数据说明系统能力，也说明性能边界

在指定浏览负载下，**30 RPS、300 秒的稳态测试通过**，稳态 p95 为 **26 ms**，全程 12,060 次 HTTP 请求均返回 200，未观察到超时。继续提高至 45 RPS 时，多轮观察到延迟突增、部分虚拟用户执行失败和后段恢复。

这让我能够明确指出一个**已经验证健康的工作点**和一个**重复出现退化的负载水平**，而不是仅凭少数 200 响应宣称系统没有瓶颈。精确容量上限仍未测定。

[容量实验与原始结论](docs/performance/stage7-closeout.md) · [实验索引](evidence/stage7/README.md)

## 代码与证据在哪里

| 目录 | 内容 |
|---|---|
| [infra/](infra/) | Kubernetes 应用、Argo CD、监控、Registry、部署资源 |
| [scripts/](scripts/) | 镜像准备、部署检查、订单备份与恢复脚本 |
| [.github/workflows/](.github/workflows/) | CI 静态检查及验证流程 |
| [tests/](tests/) | Prometheus 告警测试与性能场景 |
| [docs/incidents/](docs/incidents/) | 故障记录和排障过程 |
| [docs/runbooks/](docs/runbooks/) | 部署与恢复操作说明 |
| [evidence/](evidence/) | GitOps、容量等实验记录 |
| [docs/portfolio/architecture.md](docs/portfolio/architecture.md) | 项目拓扑与证据入口 |

历史工作按 Stage 0～8 组织，其中 Stage 8 是成果整理阶段；对应的技术记录保存在各目录。已有 [stage7-v0.8 Release](https://github.com/wanghaibing07/retail-reliability-lab/releases/tag/stage7-v0.8) 可用于回看封板版本。

## 实验范围

实验运行于共享物理宿主的三节点 Kubernetes 环境。上述结论来自对应的受控实验和历史验收，不代表集群此刻在线或生产环境高可用；节点本地存储不提供跨节点复制。容量结果针对固定的只读浏览场景，订单恢复验证针对 PostgreSQL，均有原始文档可以复核。
