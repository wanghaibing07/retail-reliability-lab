# 五个核心工程与排障故事

统一按“背景 → 动作 → 证据 → 结果 → 边界”讲述。主动演练明确叫演练，风险整改明确叫整改，实际意外故障才叫 Incident。以下没有公司生产事故口径。

| 故事 | 性质 | 最适合回答 |
| --- | --- | --- |
| 1：GitOps 自愈与控制链路排障 | 配置漂移演练；另含真实 Incident #003 | GitOps 怎么验证？真实网络故障怎么排？ |
| 2：指标驱动告警 | 受控探测判据演练 | 装了监控后怎么证明它有效？ |
| 3：PostgreSQL 恢复 | 数据风险整改与恢复演练 | 备份怎么验收？StatefulSet 等于持久化吗？ |
| 4：readiness 发布失败 | 单变量受控发布故障 | CI 过了为什么上线失败？怎么恢复？ |
| 5：容量判断 | 性能实验与环境限制封板 | 如何判断瓶颈和容量？何时不调参？ |

## 故事 1：GitOps 自愈与控制链路排障

### 主故事：配置漂移演练

**背景。** Git 声明 UI 为两个副本，需要证明 Argo CD 能纠正集群侧的手工偏差，而不是只证明安装成功。

**动作。** 保持 Git 不变，手工把 live Deployment 改成一个副本。启用 Self Heal 后观察恢复，没有再提交 Git 变更，也没有 Manual Sync。Auto Prune 则单独拿一次性 ConfigMap 验证；三个有状态 StatefulSet 设置 Prune=confirm，避免用数据库测试清理。

**证据与结果。** 自愈后 `replicas=2, ready=2`、Argo Synced/Healthy；Prune probe 在 Git 删除后由 Argo 自动移除，业务验证通过。两次实验是独立验证，不能说自愈实验同时证明了 Prune：自愈现场记录中 prune=false，自动清理是后来单独启用验证的。

**口述。** “我把 Git 中的 UI 两副本当作基准，故意把集群改成一副本，观察 Argo 自动恢复。之后独立用一次性 ConfigMap 验证清理，不对数据库做删除实验。这样我验证了期望状态会被持续维护，同时保留删除边界。”

**边界。** 配置恢复不等于业务逻辑修复；Prune 保护不等于备份。Argo 与 Git 访问仍有自身依赖。

证据：[Stage 3](../gitops/stage3-gitops.md)、[自愈现场](../../evidence/gitops-self-heal/after.txt)、[清理证据](../../evidence/gitops-auto-prune/README.md)。

### 真实故障补充：Incident #003

面试官要“意外遇到的故障”时，使用这一段，不把自愈演练冒充事故。

“Argo Application 曾出现 Unknown 和 ComparisonError，repo-server 报获取 Git refs 超时。我先区分这是交付控制链路失败，不能直接判定业务应用停机；然后分别从节点、Pod 和 repo-server 做重复网络测试，并在重建后结合抓包与 DNS、Flannel、SNAT 等检查缩小边界。证据支持 GitHub 直连外部路径间歇不稳定，但不能锁定唯一上游设备。我用仓库级代理缓解，并保留 Git 重试控制。代理路径在 worker2 和 repo-server 的 git ls-remote 验证各 10/10 通过，但这不是原始直连路径已修复。”

追问“是不是 VMware NAT / Flannel 的问题”：早期定位后来被新证据修订，最终结论不能只停留在 VMware guest 网络，更不能指定 Flannel 为唯一根因。证据：[Incident #003 完整排查](../incidents/003-argocd-repo-server-github-timeout/README.md)。

## 故事 2：指标驱动告警，业务仍然正常

**背景。** 需要证明探测指标、告警规则、Alertmanager 和邮箱形成闭环，单独发一封测试邮件不足以证明规则真的触发。

**动作。** 先通过独立测试告警验证 SMTP 通知。再经 PR #33 将 Blackbox 的接受码从 200 改为 418；UI 实际仍返回 200，因此探测判据失败。用指标和告警状态确认链路，再经 PR #34 恢复接受码。

**证据与结果。** 故障判据期间 `up=1, probe_success=0`，规则进入 pending/firing，收件箱收到 `RetailUIProbeFailed` 触发邮件；恢复后 `probe_success=1`、规则 inactive，并收到同一告警的 RESOLVED 邮件。Git 恢复后的文件树与注入前一致。

**口述。** “我没有停业务，而是让探测器只接受 418，正常的 200 因而被判失败。这样既能验证指标到规则再到邮件的整条链路，也能控制影响。恢复判据后，指标、规则和恢复邮件都确认正常。”

**边界。** 这是探测判据故障，不是真实 UI 停机；未精确采集首次指标失败和收件时刻，不计算检测时间或平均恢复时间。单副本、集群内监控不能保证全集群失联后仍发邮件。

| 追问 | 回答 |
| --- | --- |
| up=1 为什么还告警？ | Prometheus 成功抓到探测器数据，不等于探测业务成功；业务探测结果看 probe_success |
| API 测试告警和这个演练差在哪？ | 前者证明发信与恢复通知，后者还经过真实探测指标和 Prometheus 规则评估 |

证据：[SMTP 测试](../observability/stage4-email-notifications.md)、[指标驱动演练](../observability/stage4-metric-driven-alert-drill.md)、[Stage 4 边界](../observability/stage4-closeout.md)。

## 故事 3：从“有备份文件”到“应用能读回数据”

**背景。** Orders PostgreSQL 用 emptyDir，即使采用 StatefulSet，Pod 删除后仍有数据丢失风险。

**动作。** 先确认业务订单作为恢复标记；用 `pg_dump -Fc` 备份，检查归档可读和 SHA256，将副本保存到 master。再在 worker2 的隔离 PostgreSQL、Service 和 PVC 中执行恢复，并用数据库和匹配版本 Orders API 读回订单。维护窗口冻结写入后生成 final backup，再迁移到 Retain PVC；恢复服务后写入新订单，删除重建数据库 Pod 再检查新旧数据。

**证据与结果。** 隔离恢复及应用读回通过，单次恢复开始到应用验证为 81.285s。迁移后旧订单、新订单存在，Pod UID 改变后两条记录仍能从数据库和 API 读取。受控实验未观察到已确认 Orders 记录丢失。

**口述。** “备份成功不代表能恢复。我先在隔离实例中恢复并从应用读回订单，才在冻结写入的维护窗口迁移正式数据库。最后通过重建 Pod 检查旧订单和新订单，证明数据不再只依赖 Pod 的临时目录。”

**边界。** master 与 worker 共享物理宿主，副本只是离开源 VM，不是异地备份。只覆盖 Orders PostgreSQL；没有持续备份、PITR 或跨节点自动存储故障转移，不承诺 RPO=0 或固定生产 RTO。

| 追问 | 回答 |
| --- | --- |
| SHA256 能证明什么？ | 证明副本字节与源归档一致，不能单独证明数据库和应用能使用恢复数据 |
| Retain 是什么保护？ | 保留 PV 的回收策略，不是跨节点复制，也不自动恢复丢失节点上的数据 |
| 为什么冻结写入？ | 让 final backup 与受控迁移期间的数据边界明确，不能把单库备份当作全微服务一致性快照 |

证据：[Stage 5](../backup/stage5-closeout.md)、[隔离恢复证据](../evidence/stage5/20260928T070335Z-9dc19d58/README.md)、[生产 PVC 迁移证据](../evidence/stage5/production-pvc-cutover/README.md)、[备份脚本](../../scripts/backup-orders.sh)。

## 故事 4：readiness 发布失败与 Git 恢复

**背景。** 静态 CI 无法保证运行时正确，需要验证错误发布能被发现、隔离，并在 GitOps 模式下恢复。

**动作。** 保持镜像不变，只将 UI readiness 路径改成不存在的路径。提前设置两副本、`maxUnavailable=0`、`maxSurge=1`、`progressDeadlineSeconds=120` 和发布停滞告警。上线后同时检查 Pod、ReplicaSet、EndpointSlice、入口 HTTP 和 Deployment condition。恢复时确认合并父提交，通过 `git revert -m 1`、PR、CI、合并和 Argo 同步恢复。

**证据与结果。** 新 Pod Running/NotReady，探针 HTTP 404；旧两个副本 Ready，坏 Pod 的 endpoint ready=false。观测的 HTTP 样本保持 200。Deployment 出现 ProgressDeadlineExceeded，rollout status 非零，告警 firing。恢复后两个健康 Ready 后端、HTTP 200、verify.sh 通过、告警 inactive。

**口述。** “故障只改 readiness，CI 检查能通过，但运行时新 Pod 不能就绪。因为不允许减少可用副本，旧两个实例继续服务。我用 EndpointSlice 证明坏 Pod 没进入 Ready 后端，再通过发布条件和告警确认失败。恢复是在 Git 中撤销错误变更，再由 Argo 同步，保证配置和审计记录一致。”

**边界。** 主动演练，不冒充真实生产事故。41s 是恢复合并到 Argo Healthy 的观测区间；坏合并到最终验证为 36m03s，不能缩成“事故 41 秒恢复”。没有自动回滚、金丝雀或生产零停机保证。

| 追问 | 回答 |
| --- | --- |
| 为什么不用 rollout undo？ | 在该 GitOps 策略下只改集群会与 Git 冲突，Argo 可能重新部署错误期望状态；正式恢复必须同步恢复 Git |
| 120 秒到了会怎样？ | 更新失败条件，供状态检查和告警识别；不是自动回滚开关，也不是坏 Git 合并到检测的总时长 |
| 如果坏版本仍然 Ready 呢？ | 这次 readiness 故障模型无法覆盖；业务语义错误需要其他验证，不能扩大本实验结论 |

证据：[Stage 6](../releases/stage6-closeout.md)、[EndpointSlice 与 Pod 对照](../evidence/stage6/readiness-failure-001/endpoints-with-pod-identity.txt)、[失败条件](../evidence/stage6/readiness-failure-001/deployment-conditions-failed.txt)、[恢复证据](../evidence/stage6/readiness-failure-001/README.md)。

## 故事 5：容量实验中承认无效与未确定

**背景。** 单次压测超时可能受预热、环境或生成器影响；需要先保证实验能解释结果，再谈容量与瓶颈。

**动作。** 固定只读浏览场景、版本和负载身份；要求测试前验证、固定预热、正式负载、客户端日志、时序指标、生成器 CPU/节流及测试后验证完整。第一次退化记为 SUSPECT_FAILURE，再用清理环境后的同负载确认。后续延长升载与稳定区间，观察退化是否还出现。

**证据与结果。** E11 稳态约 29.997 RPS、300s，稳态 hook p95/p99 为 26/48ms，全程 12060 请求均为 200，无 failed/skipped VU，生成器峰值约 0.324 核且配额节流为零，测试后健康验证通过。E12/E14/E15 在 45 RPS 出现可重复阶段性退化，E15 测量区间有 44 个 >2s 慢请求触发记录，但后段恢复。

**口述。** “我能证明固定只读场景在 30 RPS 下健康跑了 300 秒，也能重复观察 45 RPS 的阶段性退化。39 RPS 的一次测试请求虽然很好，但缺测试后验证和时序指标，必须作废。另一次只在预热失败，不能说正式 39 RPS 失败。环境压力与慢请求有关联，却没唯一证明哪个组件是瓶颈，因此我没有为了得到优化结论去调参。”

**边界。** 30 是已验证健康点，不是最大容量；45 不是硬上限或永久不可持续点；30～45 只是已测调查范围，不是数学证明的精确拐点区间。S7-F 未新增优化，不编造前后收益，不重新开放 Stage 7。

| 追问 | 回答 |
| --- | --- |
| E16 为什么无效？ | 缺正式 post-health、required query_range、完整 restart/OOM diff 和 generator 证据；后来健康不能补成当时完整 |
| E17/E18 有什么区别？ | E17 预热失败、formal 未测，结果为 INVALID；E18 未执行，NOT_STARTED 是生命周期状态，不是第五类实验结果 |
| 生成器不是瓶颈吗？ | 没有有效实验最终证明 GENERATOR_LIMITED；E11 负载完整交付、CPU 低于限额且无节流，仍不能泛化排除所有环境影响 |
| 为什么不直接加副本或 CPU？ | 运行时压力、iowait 和内存现象未形成唯一因果证据，盲目改动会让结果更难解释；本阶段按环境限制封板 |

正式结果枚举保持 HEALTHY / SUSPECT_FAILURE / INVALID / GENERATOR_LIMITED。E16、E17 都是 INVALID；E18 的 formal result 为 N/A。稳态 hook 与全程摘要、不同阶段计数不可拼接计算错误率；12060 是 E11 全程请求数，不是 300 秒稳态请求数。

证据：[Stage 7](../performance/stage7-closeout.md)、[实验登记表](../../evidence/stage7/experiment-register.csv)、[公开汇总及原始归档哈希](../../evidence/stage7/README.md)。GitHub 不承载完整原始日志；需回到原执行工作区审计原始归档。

## 使用顺序

简历投递先选 [3～5 条结果](resume-bullets.md)；面试先说 [60 秒／3 分钟版本](interview-guide.md)，再按追问进入一个故事。只背每个故事的“问题、动作、关键证据、结论边界”四点，细节通过链接核对。已有工程证据足够，不为排练重新启动 VM 或运行压测。
