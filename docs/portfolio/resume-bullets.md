# 简历项目条目

项目名称：**Retail Reliability Lab｜Kubernetes 可靠性工程实验室**  
项目性质：个人实验项目，基于 AWS Retail Store Sample App v1.6.2；业务应用来自上游。  
项目链接：[GitHub](https://github.com/wanghaibing07/retail-reliability-lab)

以下描述依据 Stage 0～7 已记录的工作。项目日期按本人真实开始与结束时间填写，不补造任职、团队或生产经历。

## 推荐条目：按岗位选 3～5 条

1. 基于三节点 Kubernetes 搭建可靠性实验室，编写部署与分层验证脚本，结合 GitHub Actions 和 Argo CD 验证 PR 检查、自动同步、自愈及资源清理流程，并为有状态工作负载设置删除确认保护。
2. 搭建 Prometheus、Alertmanager 与 Blackbox 监控链路，通过受控探测判据演练验证告警触发与恢复邮件，结合对象状态、应用指标和容器资源指标辅助排障，并验证发布停滞告警。
3. 完成 Orders PostgreSQL 逻辑备份、SHA256 校验、跨 VM 隔离恢复及数据库/API 数据读回验证，将数据从 emptyDir 迁移至 Retain PVC，并验证 Pod 重建后新旧订单保留。
4. 设计 UI readiness 发布故障演练，以双副本、maxUnavailable=0 和 maxSurge=1 保留旧健康实例，验证坏 Pod 不进入 Ready 后端及发布停滞告警，并经 Git revert、CI 和 Argo CD 恢复服务状态。
5. 使用 Artillery 与 Prometheus 执行只读浏览容量实验，验证 30 RPS 下健康运行 300 秒，在 45 RPS 重复观察到阶段性退化；因 39 RPS 证据不完整而不纳入有效容量结论，未在因果证据不足时盲目调参。

| 条目 | 最短证据入口 | 能讲清的一个追问 |
| --- | --- | --- |
| 1：交付与自动化 | [部署验证脚本](../../scripts/verify.sh)、[Stage 3](../gitops/stage3-gitops.md)、[自愈实测](../../evidence/gitops-self-heal/after.txt)、[Prune 实测](../../evidence/gitops-auto-prune/README.md) | 为什么集群手工改成 1 副本后又变回 2？ |
| 2：监控与告警 | [Stage 4 指标驱动演练](../observability/stage4-metric-driven-alert-drill.md)、[抓取配置](../../infra/observability/prometheus/prometheus.yml)、[Stage 6](../releases/stage6-closeout.md) | 为什么探测器 up=1 仍然可能告警？ |
| 3：数据恢复 | [Stage 5](../backup/stage5-closeout.md)、[恢复证据](../evidence/stage5/)、[备份脚本](../../scripts/backup-orders.sh) | 为什么 SHA256 一致还要实际恢复并读回订单？ |
| 4：发布失败 | [Stage 6](../releases/stage6-closeout.md)、[原始观测](../evidence/stage6/readiness-failure-001/) | 为什么 CI 通过但新 Pod 不能接流量？ |
| 5：容量判断 | [Stage 7](../performance/stage7-closeout.md)、[实验登记表](../../evidence/stage7/experiment-register.csv) | 为什么 45 RPS 不是最大容量？ |

## 按目标岗位选重点

| 投递方向 | 推荐组合 | 面试优先故事 |
| --- | --- | --- |
| Linux 运维 / NOC / 技术支持实习 | 1、2、3 | [GitOps 链路真实超时排障](incident-stories.md#故事-1gitops-自愈与控制链路排障)，再讲监控或恢复 |
| 云平台运维 / Kubernetes 实习 | 1、3、4 | readiness 发布失败、数据恢复 |
| SRE 方向实习 | 1、2、4、5；版面允许再加 3 | 发布失败与容量证据判断 |

先用条目说明结果，再按追问展开工具。技术栈可另用一行：Linux / Shell / Git / Kubernetes / GitHub Actions / Argo CD / Prometheus / PostgreSQL / Artillery。上述是实际使用范围，不等价于“精通”。

## 数字使用口径

| 数字 | 可以写的含义 | 必须避免的扩大解释 |
| --- | --- | --- |
| 两次重建约 4m29s、3m47s | [Stage 1 的两次受控 destroy→deploy→verify](../../README.md#3-可重复部署) | 从零安装集群或冷拉全部镜像只需这个时间 |
| 隔离恢复到应用验证 81.285s | [Stage 5 的单次实测区间](../backup/stage5-closeout.md) | 生产 RTO 保证，或整个 Retail 的恢复时长 |
| 恢复合并到 Argo Healthy 41s | [Stage 6 的一个恢复区间](../releases/stage6-closeout.md) | 整起事故只持续 41s、平均恢复时间 41s |
| 30 RPS / 300s | 固定只读浏览负载的已验证健康点 | 最大容量 30 RPS、全交易压测或长期可用性承诺 |
| 45 RPS | 重复观察到阶段性退化，后段恢复 | 硬上限、唯一瓶颈已定位、永久不能持续 |

E16 为 INVALID，E17 只在预热失败且正式实验未测，E18 为 NOT_STARTED 生命周期状态。统一说“39 RPS 未取得有效资格结论”，不能写“39 RPS 失败”。S7-F 未新增优化不代表此前没有 UI async 修复；不编造优化前后收益。

简历条目只覆盖实验室实测：不写生产级高可用、完整灾备、生产零停机，也不把 AWS 业务样例写成本人从零开发的电商系统。
