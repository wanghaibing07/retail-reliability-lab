# 用项目证据回答面试追问

24 题覆盖 Linux、网络、Kubernetes、GitOps、监控、恢复和容量。每题先回答，再展开核对“短答 → 项目证据 → 下一层追问”。命令是排障思路，不是 Stage 8 重新启动实验室的执行要求。

先练下表的 12 道核心题；能说明动作与证据后，再练扩展题。每次任选三题，先脱稿回答 30～60 秒，核对后只记自己漏掉的关键点，隔一段时间换题复述。题库是练习用的，面试开场仍用 [分层讲解](interview-guide.md)。

| 方向 | 先练 | 再练 | 最短故事入口 |
| --- | --- | --- | --- |
| Linux / 网络 | Q01、Q04 | Q02、Q03、Q05、Q06 | [真实 GitHub 超时](incident-stories.md#真实故障补充incident-003) |
| Kubernetes | Q07、Q09、Q10 | Q08 | [readiness 发布失败](incident-stories.md#故事-4readiness-发布失败与-git-恢复) |
| GitOps | Q11、Q13 | Q12、Q14 | [自愈与控制链路](incident-stories.md#故事-1gitops-自愈与控制链路排障) |
| Monitoring | Q16 | Q15、Q17 | [指标驱动告警](incident-stories.md#故事-2指标驱动告警业务仍然正常) |
| Backup / Restore | Q18、Q19 | Q20 | [应用读回恢复数据](incident-stories.md#故事-3从有备份文件到应用能读回数据) |
| Capacity | Q22、Q23 | Q21、Q24 | [容量与无效证据](incident-stories.md#故事-5容量实验中承认无效与未确定) |

## Linux 与网络

### Q01：load average 高，能直接判断 CPU 不够吗？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 不能。Linux load average 包含 runnable 与不可中断等待任务的 1/5/15 分钟平均，不是 CPU 利用率。先结合 CPU、运行队列、阻塞任务和时间窗口判断。

**项目：** Stage 7 同时出现高 runnable queue、D-state、iowait 和运行时活动，不能只取 load 数值宣布应用 CPU 是瓶颈。[观测与归因限制](../performance/stage7-closeout.md#red--use-and-s7-f-decision)。概念：[Linux loadavg](https://man7.org/linux/man-pages/man5/proc_loadavg.5.html)。

**追问：** 运行队列与 load average 有什么不同？前者看当前可运行任务，后者有时间平均且含 D-state；比较时还要知道核数和负载身份。

</details>

### Q02：D-state 和高 iowait 能证明磁盘是唯一瓶颈吗？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** D-state 是不可中断等待，常与 I/O 有关；iowait 是 CPU 时间记账信号，多核下解释有局限。两者都不能单独锁定具体磁盘或根因。

**项目：** E14 的 iowait、blocked 与 D-state 和慢请求重叠，但记录只支持相关性。应对齐任务、等待位置、设备和宿主观测；已有采样不足，不补造因果链。[Stage 7](../performance/stage7-closeout.md#red--use-and-s7-f-decision)。概念：[loadavg 的任务状态](https://man7.org/linux/man-pages/man5/proc_loadavg.5.html)、[iowait 记账限制](https://man7.org/linux/man-pages/man5/proc_stat.5.html)。

**追问：** 下一步查什么？说明会按当时任务等待、I/O 延迟/队列和 VM/宿主边界取证；不要声称这些进一步证据已经完整取得。

</details>

### Q03：CPU 使用量低于 limit，为什么仍不能排除所有资源等待？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 使用量、配额节流和等待是不同信号。CFS 配额限制 CPU 时间；平均利用率低也要查瞬时节流、负载交付和其他资源。

**项目：** E11 generator 峰值约 0.324 核、limit=1 核、CFS=0，并且负载完整交付，支持该轮生成器没有被 CPU 配额限制；不能把它扩大成所有轮次或所有资源都无影响。[E11](../performance/stage7-closeout.md#30-rps-qualified-healthy-point-e11)。概念：[Linux CFS bandwidth](https://docs.kernel.org/scheduler/sched-bwc.html)。

**追问：** 为什么 Git smoke Job 的 500m 不能拿来解释正式实验？参数身份不同，正式 Job 与报告中的限额才是该轮证据。

</details>

### Q04：connection refused 与 timeout 的排障方向有什么不同？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** connect 的 ECONNREFUSED 表示连接被拒绝；常见是目标无监听，也需考虑路径上的主动拒绝。timeout 表示未在期限内完成，先区分 DNS、连接、TLS 和响应阶段。

**项目：** Artillery 的 ETIMEDOUT 不能一律解释成 TCP 连接失败。Incident #003 用 DNS、TCP 探测和抓包缩小 GitHub 访问故障边界，不能凭“超时”直接改 CoreDNS。[排查记录](../incidents/003-argocd-repo-server-github-timeout/README.md)。概念：[connect 错误](https://man7.org/linux/man-pages/man2/connect.2.html)。

**追问：** SYN 已发出却没有响应证明什么？支持连接路径异常，仍不能唯一指定丢包设备或上游责任方。

</details>

### Q05：Pod 里域名访问失败，怎么区分 DNS 与后续连接故障？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 先看 Pod 的 resolv.conf、查询结果和耗时，再对解析出的地址测试相应协议。集群 Service 名称与外部 GitHub 域名走的解析和访问路径需要分开检查。

**项目：** Incident #003 跨节点、Pod、repo-server 重复验证，最终没有把健康的 CoreDNS 或 Flannel 定为根因。[最终结论](../incidents/003-argocd-repo-server-github-timeout/README.md)。概念：[Kubernetes DNS](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)。

**追问：** DNS 成功就能排除网络吗？不能，它只说明该次名称解析成功，后续 TCP/TLS/HTTP 仍要分层验证。

</details>

### Q06：NodePort 到 UI 的请求不通，你按什么顺序缩小范围？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 先复现入口错误，核对 Service 的 selector、port/targetPort、EndpointSlice 后端与 ready 状态；再比较 Pod IP、ClusterIP 与 NodePort，结合 Pod 日志和节点转发路径定位。

**项目：** verify.sh 检查工作负载、Service 后端和业务 HTTP；Stage 6 将坏 Pod UID 与 ready=false 的 endpoint 对上，证明了当时的后端状态。不能给未部署的 Nginx/Ingress 编一个排障经历。[验证脚本](../../scripts/verify.sh)、[后端对照](../evidence/stage6/readiness-failure-001/endpoints-with-pod-identity.txt)。概念：[Service](https://kubernetes.io/docs/concepts/services-networking/service/)、[EndpointSlice](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/)。

**追问：** Service 是代理进程吗？它是声明的访问抽象；实际转发由集群的 Service 实现处理，不能把每个 Service 想成独立进程。

</details>

## Kubernetes 与 GitOps

### Q07：为什么新 Pod Running，发布仍然卡住？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** Running 是生命周期阶段，Ready 是可服务条件。先对照 Pod conditions、探针失败事件、ReplicaSet 和 Deployment 进展，再验证后端与入口。

**项目：** Stage 6 新 UI Pod 正在运行，但错误 readiness 路径返回 404；旧两个副本 Ready，坏 endpoint ready=false。[发布证据](../evidence/stage6/readiness-failure-001/README.md)。概念：[Kubernetes probes](https://kubernetes.io/docs/concepts/workloads/pods/probes/)。

**追问：** 所有 ready=false endpoint 都绝不可能接流量吗？不要泛化；需考虑 Service 配置、终止语义和直接 Pod IP 访问。本项目证明的是该故障样本的 Ready 后端状态。

</details>

### Q08：readiness、liveness 和 startup probe 分别解决什么？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** readiness 控制可接流量状态；liveness 失败达到阈值后触发容器重启；startup 给初始化留出独立判据，成功前暂不执行另外两种探针。

**项目：** Stage 6 只改 readiness，镜像不变。故障模型是不能就绪，不是依赖容器崩溃产生重启。[单变量演练](../releases/stage6-closeout.md)。概念：[探针语义与风险](https://kubernetes.io/docs/concepts/workloads/pods/probes/)。

**追问：** 为什么不直接把 liveness 也改严格？错误的重启判据可能放大负载下的故障；配置必须对应实际可恢复的失败模式。

</details>

### Q09：maxUnavailable=0、maxSurge=1 怎么限制坏发布影响？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 滚动更新不允许减少可用副本，并允许额外创建一个。它依赖旧副本仍健康及资源能容纳新副本，不能保证所有故障都零影响。

**项目：** UI desired=2，坏新副本不能 Ready，旧两个实例继续服务，入口样本仍为 200。[Stage 6](../releases/stage6-closeout.md)。概念：[Deployment 滚动更新](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)。

**追问：** 同时最多三个 Pod，因此内存永远不超三个吗？不能如此承诺；终止中的 Pod 和回收延迟会影响实际 Pod 数及资源峰值。

</details>

### Q10：ProgressDeadlineExceeded 会自动回滚吗？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 不会。它是 Deployment 未按期限取得进展的状态信号，需由状态检查、告警和恢复流程处理。

**项目：** deadline=120s，观测到 Progressing=False / ProgressDeadlineExceeded、rollout status 非零及告警 firing；实际恢复依靠 Git revert。[失败条件](../evidence/stage6/readiness-failure-001/deployment-conditions-failed.txt)。概念：[Deployment 失败处理](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)。

**追问：** 120 秒是从坏 Git 合并开始算吗？不是该实验的端到端时长，还涉及 CI、Argo、控制器观察及告警评估等阶段。

</details>

### Q11：CI 与 Argo CD 各自证明什么？为什么 CI 过了还会失败？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** CI 验证提交满足已编码的静态与测试规则；Argo CD 对 Git 声明状态做集群协调。两者都不能单独保证业务正确。

**项目：** CI 检查 Shell、manifest、镜像与监控规则；不存在的 readiness URL 仍符合 schema，所以部署后才 NotReady。Argo Synced 只说明同步状态，仍可 Degraded。[CI 范围](../../.github/workflows/ci.yml)、[反例](../releases/stage6-closeout.md)。

**追问：** 是不是应该给 CI 加所有集成测试？先说明静态检查边界和运行时验收需求；本项目未实现全覆盖集成测试，不为回答而编造新能力。

</details>

### Q12：Self Heal 与 Prune 有什么区别，如何安全验证？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** Self Heal 纠正 live 与 Git 的漂移；Prune 清理已从 Git 删除的受管资源。删除需要额外保护。

**项目：** UI 手工缩为一副本后自动回到 Git 的两副本；这是 prune=false 时的独立自愈测试。后来拿一次性 ConfigMap 验证 Auto Prune，数据库等 StatefulSet 用 Prune=confirm。[自愈](../../evidence/gitops-self-heal/after.txt)、[清理](../../evidence/gitops-auto-prune/README.md)。概念：[Argo 自动同步](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)。

**追问：** 删除保护会备份数据库吗？不会，协调策略、存储回收策略和数据备份分别解决不同问题。

</details>

### Q13：为什么用 Git revert 恢复，而不是 kubectl rollout undo？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 该 GitOps 流程以 Git 为 desired state，只回滚 live 会留下冲突。撤销错误 Git 变更后，经 PR/CI/Argo 恢复，保留审计链。

**项目：** Stage 6 使用 git revert -m 1 撤销坏合并，核对父提交后恢复。[恢复流程](../releases/stage6-closeout.md)。概念：[git revert](https://git-scm.com/docs/git-revert)。

**追问：** -m 1 是回退一个版本吗？不是，它选择合并提交的 mainline 父提交。紧急 live 操作若另有流程也须回写期望状态；本实验没有采用该路径。

</details>

### Q14：Argo Unknown / ComparisonError 代表业务已经停机吗？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 不能这样推断。先区分仓库比较/交付控制链路与已运行的业务，再分别检查。

**项目：** Incident #003 的 repo-server 获取 refs 超时，代理缓解后两处 git ls-remote 各 10/10 通过；这只验证代理访问路径，不证明原始直连修复。[最终证据](../incidents/003-argocd-repo-server-github-timeout/README.md)。

**追问：** 为什么“加重试成功一次”还不够？间歇失败需重复观测，并区分缓解、恢复与根因证据。

</details>

## Monitoring 与 Backup / Restore

### Q15：RED 与 USE 怎么一起用于诊断？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 先用 rate/errors/duration 确认服务影响，再用 utilization/saturation/errors 查看相关资源，最后检查时序与证据边界。

**项目：** Stage 7 将慢请求、超时和负载交付与 generator/容器/节点/宿主观测对照，但资源指标未形成唯一因果链。[诊断结论](../performance/stage7-closeout.md#red--use-and-s7-f-decision)。概念：[Prometheus 在线服务指标](https://prometheus.io/docs/practices/instrumentation/)、[USE 方法作者说明](https://www.brendangregg.com/usemethod.html)。

**追问：** CPU 利用率低等于没有 saturation 吗？不能；不同资源的等待与队列要单独检查，采样粒度也会遮蔽短暂事件。

</details>

### Q16：up=1，为什么 Blackbox 仍然告警？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** up 说明 Prometheus 抓取成功，不说明业务探测成功；探测结果看 probe_success，并结合 HTTP 状态与探测耗时。

**项目：** 接受码临时从 200 改为 418，UI 仍回 200；up=1、probe_success=0，触发邮件，恢复配置后收到 resolved。[指标驱动演练](../observability/stage4-metric-driven-alert-drill.md)。

**追问：** 测试邮件和这次演练差在哪？邮件测试只验证通知路径，本次还经过真实指标与 Prometheus 规则；都不等于全集群停机后的外部监控能力。

</details>

### Q17：所有请求 HTTP 200 就够了吗？p95 应怎样引用？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 还要看延迟、未完成/超时请求、实际负载及测试后健康。分位数必须说明统计对象与时间窗口，业务正确性还需相应数据验证。

**项目：** E11 全程 12060 个 200；300s 稳态只有 8999 个成功请求-start hooks，hook p95=26ms；全程 Artillery p95=26.8ms。不能把全程计数放进稳态窗口。query_range step=5s 也不等于 scrape=5s，实际约 30s。[E11 与方法](../performance/stage7-closeout.md)。

**追问：** 为什么不能平均几个阶段的 p95？分位数需要对应样本分布；直接平均会失去全体样本含义。

</details>

### Q18：SHA256 和 pg_restore --list 通过，还要做什么？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 哈希验证副本字节一致，list 验证归档可解析；还需实际恢复，再从数据库和应用读回业务标记。

**项目：** Orders pg_dump -Fc 后在 worker2 隔离恢复，用匹配 Orders API 读回指定订单，才进入正式 PVC 迁移。[隔离恢复证据](../evidence/stage5/20260928T070335Z-9dc19d58/README.md)。概念：[PostgreSQL 16 pg_dump 的单库范围](https://www.postgresql.org/docs/16/app-pgdump.html)。

**追问：** 为什么不直接拿该文件说整个 Retail 恢复成功？其他数据库与跨服务一致性不在这次单库验证范围。

</details>

### Q19：StatefulSet、PVC、Retain 等于可靠灾备吗？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 不等于。控制器身份、数据卷生命周期、回收策略和备份分别看；Retain 不自动提供复制。

**项目：** Orders 原来是 StatefulSet + emptyDir，仍存在 Pod 删除丢数据风险。迁移到 worker2 的 local-path-retain PVC 后，Pod UID 改变而新旧订单保留；未验证节点丢失后的自动恢复。[Stage 5](../backup/stage5-closeout.md)。概念：[emptyDir](https://kubernetes.io/docs/concepts/storage/volumes/)、[PV Retain](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)。

**追问：** master 的备份算异地吗？它离开源数据库 VM，但各 VM 同一物理宿主，不能叫异地。

</details>

### Q20：为什么 81.285s 不能写成生产 RTO？41s 能写成 MTTR 吗？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 先定义开始、结束和包含步骤。一次区间观测不构成生产目标保证，更不是多次事故的平均恢复时间。

**项目：** 81.285s 是隔离恢复开始到应用验证；41s 是恢复合并到 Argo Healthy，坏合并到最终验证为 36m03s。冻结写入也不证明持续 RPO=0。[Stage 5](../backup/stage5-closeout.md)、[Stage 6](../releases/stage6-closeout.md)。

**追问：** 能给哪些数字？可以给单次观测与完整区间，并明确实验室、单库或受控发布范围。

</details>

## Performance / Capacity

### Q21：Artillery arrivalRate 为什么不等于 HTTP RPS？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** arrivalRate 是新虚拟用户到达率；每个用户的请求数、流程耗时和失败会改变实际 HTTP 流量。

**项目：** 固定 browse 配置每 VU 三个 GET，10 VU/s 对应目标约 30 HTTP RPS；仍要用实际 hooks、完成率和错误验证交付。[固定场景](../../tests/performance/browse.yml)、[正式方法](../performance/stage7-closeout.md#fixed-identity-and-method)。概念：[Artillery phases](https://www.artillery.io/docs/reference/test-script)。

**追问：** skipped VU 能忽略吗？不能，它表示计划负载未完整创建；需结合失败、请求和生成器状态解释。

</details>

### Q22：30 RPS 健康、45 RPS 退化，能说最大容量找到了吗？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 不能。30 RPS / 300s 是已验证健康点；45 RPS 重复阶段性退化且后段恢复，不是硬上限。

**项目：** E11 与 E12/E14/E15 分别支撑健康点与重复退化。30～45 只是已测 investigation envelope，exact knee / maximum capacity unresolved。[正式结论](../performance/stage7-closeout.md#capacity-conclusion-and-operational-recommendation)。推理方法：[Google SRE NALSD](https://sre.google/workbook/non-abstract-design/)。

**追问：** 为什么没有给一个漂亮的最大数字？试验范围、有效资格和环境约束不支持；Stage 7 已按该边界封板。

</details>

### Q23：E16 请求健康为什么作废？E17/E18 又有什么区别？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 实验资格不只看请求。E16 缺正式 post-health、required query_range、restart/OOM diff 和 generator 证据，INVALID；E17 warm-up 失败、formal 未测，也是 INVALID；E18 未执行，是 NOT_STARTED 生命周期，formal=N/A。

**项目：** 三者都不能给 39 RPS 下正式健康或失败结论。正式结果枚举仍为 HEALTHY / SUSPECT_FAILURE / INVALID / GENERATOR_LIMITED，NOT_STARTED 不新增为第五类。[39 RPS 记录](../performance/stage7-closeout.md#why-39-rps-is-inconclusive)。

**追问：** 之后验证健康能补回 E16 吗？不能证明原正式实验的缺失区间；不事后美化资格。

</details>

### Q24：观察到资源压力，为什么最后没有优化？如何判断 generator limited？

<details>
<summary>核对短答、证据与追问</summary>

**短答：** 先证明计划负载是否交付，检查生成器资源与节流，再对齐服务影响和系统资源。相关性不足以指定组件调参。

**项目：** E11 完整交付、生成器无 CFS 节流；本轮没有有效实验最终证明 GENERATOR_LIMITED。45 RPS 的资源相关现象又未唯一证明 UI/Carts/数据库或 generator 是瓶颈，因此 S7-F 未新增优化。[证据与 no-change 决策](../performance/stage7-closeout.md#red--use-and-s7-f-decision)。

**追问：** “没有优化”是否代表项目从未修过应用？不是，既有 UI async 修复属于固定基线；不能编造 S7-F 前后性能收益，也不为本次面试准备重开实验。

</details>

## 写作方法与维护

本题库采用“情境问题 → 一句概念 → 本人动作与项目证据 → 追问边界”。这是针对本项目的编辑选择，不宣称存在普适最优模板。

- [Google Technical Writing：短句](https://developers.google.com/tech-writing/one/short-sentences)：一段回答先抓一个主要判断，必要细节再展开。
- [Diátaxis](https://diataxis.fr/)：入口供快速理解，题库供练习，原记录供核验；按读者任务组织，避免把所有材料堆在一个定义表。
- [CMU：retrieval practice](https://www.cmu.edu/teaching/resources/instructionalstrategies/activelearningstrategies/retrievalpractice/index.html)：先主动回忆，再用答案反馈修正；折叠答案服务这个练习过程。

技术链接解释一般机制，项目链接支撑本人经历。官方文档可能随版本更新，追问版本差异时应核对本项目固定版本；不要把后续新功能写进历史实测。新增或修改回答时先检查 [统一声明边界](claim-boundaries.md)，保持简历、讲稿与故事一致。
