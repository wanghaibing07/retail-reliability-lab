# 项目分层讲解

> 中文阅读入口：[先用中文看懂项目与术语](plain-language-guide.md)。工具名称、命令和正式状态字段保留原文，便于核对证据。

目标：按面试官给的时间说明背景、自己的工作、证据和边界。以下均为个人实验项目口径，不补造公司业务规模或真实生产事故。

| 可用时间 | 用法 | 材料 |
| --- | --- | --- |
| 30～60 秒 | 先回答“项目是什么”，等面试官选择方向 | [架构文档中的 60 秒版本](architecture.md#60-秒讲解) |
| 约 3 分钟 | 背景与架构 → 三项能力 → 一次故障 → 结果 | 下方完整口述稿 |
| 约 10 分钟 | 用架构图串起工程过程，给追问留下空间 | 下方六段讲解 |

时长是排练目标，不是逐字朗读保证。先讲中文含义，面试官需要时再给配置名和命令。讲述历史验证时用“当时验证”，不要把历史 Healthy 当作当前在线状态。

## 约 3 分钟口述稿

我做的是 Retail Reliability Lab，一个基于 AWS 电商微服务样例的 Kubernetes 可靠性实验室。业务代码主体来自上游，我主要做部署、交付、监控、数据恢复和故障验证。环境是本地三台 VMware 虚拟机，应用包含 UI、商品、购物车、结算、订单和各自的数据依赖，不是生产系统。

我一开始解决的是能否重复部署的问题。我把镜像准备、部署、验证和清理拆成脚本；验证不只看 Pod 运行，还检查工作负载就绪、Service 的可用后端和业务 HTTP。之后接入 GitHub Actions 做脚本和 Kubernetes 配置检查，再用 Argo CD 从 main 自动同步到集群。我验证过把 UI 手工改成一个副本后，Argo 自动恢复到 Git 中的两个副本；清理测试只删除一次性 ConfigMap，对有状态工作负载增加删除确认保护。

第二项是监控闭环。我用 Blackbox 探测 UI 入口，由 Prometheus 评估规则，Alertmanager 发邮件。演练时没有停掉业务，而是把探测接受码临时改为 418，让正常的 200 被判失败，实际收到了触发和恢复邮件。这证明了指标到通知的链路，不代表测过真实业务停机。

第三项是数据恢复。Orders PostgreSQL 起初用 emptyDir，Pod 被删除后数据有丢失风险。我做了逻辑备份与校验，把副本放到源数据库 VM 之外，在另一台 VM 隔离恢复，并从数据库和 Orders API 读回指定订单。再在冻结写入的维护窗口迁移到保留型 PVC，验证旧订单、新订单和 Pod 重建后的数据。

我最有代表性的一次故障实验是 UI 发布失败。我把 readiness 路径改错，配置能通过静态 CI，但新 Pod 返回 404、不能就绪。因为保留两个旧副本且不允许减少可用副本，坏 Pod 没成为 Ready 后端，观测样本仍返回 HTTP 200。发布超过进展期限后出现告警，我通过 Git revert、PR、CI 和 Argo 恢复，没有只在线上改配置。

最后做了只读浏览容量实验：30 RPS 健康运行 300 秒；45 RPS 重复出现阶段性退化但后段恢复；39 RPS 缺少有效资格证据。最大容量和唯一瓶颈没有确定，因此最后没有盲目调参。这个项目让我形成了先分层验证、再用证据判断和恢复的工作方式。

## 约 10 分钟讲解：六段主线

### 1. 背景、架构与职责（约 1 分钟）

我想验证的是一套微服务从能启动到能被可靠运维的过程，所以选择 AWS 已有的业务样例，重点投入运维工作，而不是重新开发电商业务。在本地三节点 Kubernetes 上，UI 通过 Service 访问 Catalog、Carts、Checkout 和 Orders。数据依赖包括 MySQL、DynamoDB Local、Redis、PostgreSQL 和 RabbitMQ，不能把它们当作同一个数据库系统。

我负责的项目工作包括部署和验证脚本、CI 检查、Argo CD 配置、监控告警、Orders PostgreSQL 恢复、发布故障和容量实验。Stage 7 固定基线还包含已记录的 UI async 修复；“最后没有新增优化”只指 S7-F，不代表之前没有代码改动。这里是个人实验室，三台 VM 共享物理宿主，所以我不把它叫作生产级高可用平台。

展示：[总体架构与服务依赖图](architecture.md)。

### 2. 自动化、CI 与 GitOps（约 1.5 分钟）

最初的问题是，手工部署成功一次，不代表下一次能重现。我把镜像预拉取、部署、验证、清理拆开，并完成过两次重建。验证脚本从 Git 中的预期对象出发，检查 Deployment、StatefulSet、Pod Ready、Service 和 EndpointSlice，最后检查入口 HTTP。这样既不会把“没启动的预期服务”漏掉，也不会把 Running 直接当作业务健康。

CI 主要解决提交前的错误：脚本语法、ShellCheck、Kustomize 渲染、清单格式和镜像标签策略。Argo CD 解决的是把通过流程进入 main 的期望状态持续同步到集群。它们分工不同，CI 本身不直接部署集群，也不保证配置的业务语义正确。

我分别验证了自动同步、自愈和清理。自愈测试中 Git 保持 UI 两副本，手工把集群改为一副本后，Argo 自动恢复到两个。清理则使用一次性 ConfigMap，避免拿数据库测试删除；三个有状态工作负载加了 Prune=confirm，allowEmpty=false 也作为防护。该保护不替代持久化和备份。

真实问题还有 repo-server 到 GitHub 间歇超时。排查后用仓库级代理和重试缓解，未把它说成唯一根因已修复。如果面试官关注网络，我可以单独展开这个真实 Incident。

证据：[Stage 3](../gitops/stage3-gitops.md)、[Incident #003](../incidents/003-argocd-repo-server-github-timeout/README.md)。

### 3. 监控与告警闭环（约 1.5 分钟）

监控我分成两类：从外面探测入口，回答用户能否访问；读取内部指标，回答应用是否慢、是否报错，工作负载和容器资源是否异常。Blackbox 提供入口探测，kube-state-metrics 提供对象状态，业务 Pod 提供原生指标，kubelet cAdvisor 提供容器资源。Prometheus 负责采样和评估规则，Alertmanager 负责路由与通知。

告警演练不是直接发一个测试邮件就结束。我先验证 SMTP 的触发与恢复通知，再通过 Git 修改探测接受码，从 200 改成 418。因为 UI 仍返回 200，探测器采集正常但判定失败，能看到 up=1、probe_success=0，再看到规则进入 pending 和 firing，收到告警邮件。恢复接受码后，指标和规则恢复，收到同一告警的 RESOLVED 邮件。

这验证了探测指标到告警通知的链路，同时保留边界：没有测真实停机或全集群失联通知，监控也不是高可用。Stage 4 的 target 数是当时快照；后续 Stage 7 增加了应用与 cAdvisor 抓取。node-exporter 未在该封板版本的 Git 清单中声明，不能把它说成已声明化能力。

证据：[指标驱动邮件演练](../observability/stage4-metric-driven-alert-drill.md)、[抓取配置](../../infra/observability/prometheus/prometheus.yml)。

### 4. 数据备份、隔离恢复与持久化（约 1.5 分钟）

Orders PostgreSQL 起初使用 emptyDir。它能跨容器重启保留，但 Pod 删除后数据会丢失，所以“用了 StatefulSet”还不等于数据已持久化。我先创建并确认一条业务订单，用它作为恢复标记，而不是只检查备份文件是否存在。

备份用 pg_dump 的自定义格式，先写临时归档，检查非空、可列出内容和 SHA256，再保存源数据库 VM 之外的副本。之后在 worker2 上用隔离的 PostgreSQL、Service 和 PVC 做真实恢复。除了数据库表和订单记录，还启动匹配版本的 Orders 应用，通过 API 读回订单，证明恢复数据可以被应用使用。一次隔离恢复到应用验证测得约 81 秒，这只是实验区间，不是生产恢复时间承诺。

迁移时先冻结 Checkout 和 Orders 写入，生成 final backup，再恢复到 worker2 的正式 Retain PVC，让 StatefulSet 接管。恢复服务后验证旧订单和新订单，并主动删除重建数据库 Pod 再读回两条记录。

该实验覆盖 Orders PostgreSQL；master 副本和两个 worker 都共享物理宿主，不是异地备份。Retain 也不代表跨节点复制或节点丢失后的自动恢复。

证据：[Stage 5](../backup/stage5-closeout.md)、[恢复 Runbook](../runbooks/orders-postgresql-restore.md)。

### 5. 受控发布失败与 Git 恢复（约 2 分钟）

我选 UI 做单变量实验，镜像保持不变，只把 readiness 路径改成不存在的地址。上线前已有两个副本、maxUnavailable=0、maxSurge=1、progressDeadlineSeconds=120，以及发布停滞告警。故障变更经过 PR 和 CI，清单结构合法，所以静态检查通过；Argo 同步后，新 Pod 虽然 Running，但探针返回 404，因此 Ready=False。

我同时看了旧、新 ReplicaSet 和 EndpointSlice，而不是只看 Pod 状态。旧两个副本仍 Ready，新副本没有成为 Ready 后端，采集到的入口请求仍返回 200。发布没有取得进展，Deployment 最终 Progressing=False，原因为 ProgressDeadlineExceeded；rollout status 返回非零，Prometheus 发布停滞告警进入 firing。业务入口探测告警当时没有触发，所以“发布失败”和“入口不可用”确实是不同状态。

恢复时先确认坏合并提交和父提交，再用 git revert -m 1 形成恢复变更，经 PR、CI、合并，由 Argo 恢复。这里的 -m 1 是选择合并提交的主线父提交，不是“回退一个版本”。恢复后检查 Git revision、Argo Synced/Healthy、两个 Ready 后端、HTTP、告警清除和 verify.sh。

恢复合并到观察 Argo Healthy 是 41 秒，但整起实验从坏合并到最终验证约 36 分钟，不能把 41 秒说成总恢复时间。120 秒是发布进展期限，不会自动触发回滚。旧实例保留也不能保证所有业务语义错误都被探针发现，更不能据此承诺生产零停机。

证据：[Stage 6](../releases/stage6-closeout.md)、[失败与恢复原始观测](../evidence/stage6/readiness-failure-001/)。

### 6. 容量实验与结论边界（约 2 分钟）

最后我使用 Artillery 产生只读浏览流量，覆盖首页、商品列表和商品详情，并结合请求量、错误、延迟以及资源使用和压力证据。生成器定向放在 master 的独立命名空间，避免直接占用 worker 的 guest 资源，但仍共享物理宿主，不叫完全隔离。每个虚拟用户配置三个请求，所以用户到达率不等于实际 HTTP RPS，要看真正交付的负载。

我要求测试前健康、固定预热、正式负载、客户端日志、时序指标、生成器资源和测试后健康都完整；Job Complete 或 HTTP 200 本身不足以给实验盖章。E11 的 30 RPS 测试包含 120 秒升载和 300 秒稳态，全程 12060 个 HTTP 请求都返回 200，失败和跳过虚拟用户为零；稳态请求 hook 的 p95 为 26ms。生成器 CPU 峰值约 0.324 核、限额 1 核、CPU 配额节流为零，测试后验证也通过。

E12、E14 和 E15 在 45 RPS 重复观察到超时或慢请求等阶段性退化，但后段恢复，所以我只说它是已测到的退化点，不说硬容量上限。E16 的 39 RPS 虽然请求表现健康，却缺少正式测试后健康、时序指标等必要证据，必须判无效；E17 预热失败，正式未测；E18 只准备了脚本。三者都不能填补有效容量结论。

我观察到运行时活动、iowait、不可中断等待任务和宿主可用内存偏低等现象，但采样粒度、指标空窗和环境稳定性限制了归因，没有唯一证明是 UI、Carts、数据库或生成器造成。因此 S7-F 没有新增调参，按环境限制封板。最终得到的是 30 RPS/300 秒的已验证健康点、45 RPS 的重复阶段性退化，以及尚未确定的精确拐点和最大容量。我的收获是知道何时证据足够、何时应承认未确定。

证据：[Stage 7](../performance/stage7-closeout.md)、[汇总及哈希索引](../../evidence/stage7/README.md)。原始日志保留在原执行工作区，未全部公开到 GitHub。

## 被打断时如何接话

| 面试官转向 | 立即进入 | 一句引导 |
| --- | --- | --- |
| “讲个最具体的故障” | [发布失败故事](incident-stories.md#故事-4readiness-发布失败与-git-恢复) | “这是主动演练，我能按变更、证据和恢复顺序展开。” |
| “有没有意外遇到的问题” | [GitOps 故事中的 Incident #003](incident-stories.md#故事-1gitops-自愈与控制链路排障) | “repo-server 访问 GitHub 的超时是真实问题，后来做了代理缓解。” |
| “哪个是你做的” | 本文第 1 段，再进入被问的具体配置 | “业务样例来自 AWS，我负责这些运维配置、脚本与验证；我可以展示对应提交和证据。” |
| “效果提升多少” | 相应封板结果 | “先确认比较区间；S7-F 没有新的优化前后对照，不能给一个提升百分比。” |

排练顺序：先能脱稿说明 60 秒版本，再选发布或恢复故事讲透，最后扩展到 3／10 分钟。面试重点是能解释动作与证据，不是背完全部数字。简历选项见 [项目条目](resume-bullets.md)，逐个案例见 [五个故事](incident-stories.md)；追问用 [折叠答案题库](interview-question-bank.md) 自测，对外措辞核对 [声明边界](claim-boundaries.md)。
