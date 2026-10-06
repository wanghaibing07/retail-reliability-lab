# 对外声明与证据边界

用于审核 README、简历、讲稿和 Release。先说本人完成的动作与实测结果，再限定环境、负载、时间和证据范围。概念依据不能替代项目实测；旧阶段的 Healthy 不是当前在线证明。

Stage 7 正式结论固定在 [stage7-v0.8 closeout](https://github.com/wanghaibing07/retail-reliability-lab/blob/stage7-v0.8/docs/performance/stage7-closeout.md)。本文件只整理表达，不重判实验、不补运行证据。

## 项目归属、环境与工程结果

| 主题 | 可以说 | 不能扩大为 | 项目证据 |
| --- | --- | --- | --- |
| 归属与职责 | 基于 AWS Retail Store Sample App，完成部署、交付、监控、恢复和故障验证；固定基线包含已记录的 UI async 修复 | 本人从零开发整套电商微服务，或业务代码全部未改动 | [上游说明](https://github.com/aws-containers/retail-store-sample-app)、[基线修复](../performance/stage7-c4/ui-async-fix.patch) |
| 环境 | 本地三节点 VMware/Kubernetes 实验室 | AWS 云上生产部署、三台独立物理宿主、生产级 HA，或实验室目前健康 | [架构与环境边界](architecture.md) |
| 重复部署 | 两次受控 destroy→deploy→verify 成功，镜像准备从部署流程中拆离 | 冷启动安装全部基础设施只需约四分钟，或所有脚本严格幂等 | [部署记录](../../README.md#3-可重复部署)、[脚本](../../scripts/) |
| CI | 检查 Shell、manifest 和镜像规则；真实发现过 SC2029 | CI PASS 保证探针、业务语义和发布运行时正确 | [CI](../../.github/workflows/ci.yml)、[发布反例](../releases/stage6-closeout.md) |
| GitOps | 自愈副本漂移；另用一次性 ConfigMap 验证 Auto Prune；有状态对象加确认保护 | 同一次实验验证全部功能，或 Prune 保护等于数据库备份 | [自愈](../../evidence/gitops-self-heal/after.txt)、[Prune](../../evidence/gitops-auto-prune/README.md) |
| 网络故障 | Incident #003 缩小到已验证 guest SNAT 之外的 GitHub 直连路径不稳定；代理路径重复验证通过 | 唯一锁定 VMware/Flannel/运营商/GitHub 为根因，或原直连已修复；控制链路异常等于业务停机 | [最终排查结论](../incidents/003-argocd-repo-server-github-timeout/README.md) |
| 告警 | 改变探测接受码，真实验证指标→规则→触发/恢复邮件；UI 当时仍返回 200 | 演练制造了真实业务停机，或 SMTP 测试邮件单独证明规则评估链路 | [指标驱动演练](../observability/stage4-metric-driven-alert-drill.md) |
| 监控范围 | 验证黑盒、对象状态、应用及容器指标；按对应阶段证据说明覆盖 | 连续 24h 无故障、99.9% 可用性、完整 SLO 达标或集群全停仍能告警；历史 node-exporter 采样等于 Git 可重复部署 | [Stage 4 限制](../observability/stage4-closeout.md)、[Git 抓取配置](../../infra/observability/prometheus/prometheus.yml)、[Stage 7](../performance/stage7-closeout.md) |
| 备份与恢复 | Orders PostgreSQL 逻辑备份、哈希校验、跨 VM 隔离恢复及 DB/API 读回；维护窗口迁移后验证 Pod 重建持久性 | 整个 Retail 一致性恢复、异地灾备、PITR、跨节点自动存储切换、RPO=0 或生产 RTO 承诺 | [Stage 5](../backup/stage5-closeout.md) |
| 发布安全 | 主动 readiness 故障下，旧健康副本保留，坏 Pod ready=false，HTTP 观测样本仍为 200；Git revert 后恢复 | 真实生产事故、自动回滚、生产零停机、所有业务错误均被探针拦住 | [Stage 6](../releases/stage6-closeout.md)、[EndpointSlice 对照](../evidence/stage6/readiness-failure-001/endpoints-with-pod-identity.txt) |

## 容量结论：固定口径

| 证据对象 | 正式口径 | 不能扩大为 |
| --- | --- | --- |
| E11，30 RPS | 固定只读浏览负载，30 RPS / 300s 已验证健康 | 最大容量 30 RPS、全交易链路压测、长期 SLO 保证 |
| E12/E14/E15，45 RPS | 重复观察到 episodic degradation，后段恢复 | 45 RPS hard ceiling、永久稳态不可持续、最大容量已确定 |
| 30～45 RPS | 已测 investigation envelope | 数学证明的 exact knee bracket；exact knee / maximum capacity 仍 unresolved |
| E16，39 RPS | formal 已运行、请求方向性健康；缺 post-health、required query_range、完整 restart/OOM diff 和 generator 证据，INVALID | 已验证健康点；事后补写即可变 HEALTHY |
| E17，39 RPS | warm-up 失败，formal NOT TESTED；INVALID | 正式 39 RPS 压测失败 |
| E18，39 RPS | 仅准备脚本，lifecycle_status=NOT_STARTED、formal_result=N/A | 39 RPS 失败；NOT_STARTED 是第五种结果分类 |
| 结果枚举 | HEALTHY / SUSPECT_FAILURE / INVALID / GENERATOR_LIMITED | 本轮有效实验已证明 GENERATOR_LIMITED；没有这样的最终资格结论 |
| S7-F | SUT_OPTIMIZATION=NOT_APPLIED，因因果证据不足而不新增调参 | 唯一瓶颈已定位；优化提升百分比；此前没有 UI async 修复 |

证据：[封板报告](../performance/stage7-closeout.md)、[实验登记表](../../evidence/stage7/experiment-register.csv)、[公开汇总与归档哈希](../../evidence/stage7/README.md)。登记表保留 E18 历史展示，须按生命周期解释；不改写归档字段来美化结果。

## 数字必须带统计范围

| 数字 | 正确范围 | 禁止拼接或改名 |
| --- | --- | --- |
| E11：4020/4020/4020 VU，12060/12060 HTTP 200 | 全程，含 120s ramp 与 300s steady；failed/skipped=0 | 12060 是 300s 稳态请求数 |
| E11：8999 hooks，约 29.997 RPS；p95/p99=26/48ms | 稳态窗口成功请求的 hook；全程 Artillery 摘要 p95/p99=26.8/46.1ms | 混用 phase/cohort 计算错误率或延迟分位数 |
| E11：generator peak≈0.324 core，limit=1 core，CFS=0 | 该正式实验完整交付负载的生成器证据 | 用 Git 中 smoke Job 的 500m limit 替代正式参数；泛化排除全部环境因素 |
| Stage 5：81.285s | 单次隔离恢复开始到应用验证 | 生产 RTO、完整 Retail 灾备时长 |
| Stage 6：41s | 恢复合并到 Argo Healthy | 全部事故耗时或 MTTR；坏合并到最终验证为 36m03s |
| Stage 7：query_range step=5s，实际 scrape 约 30s | 查询步长与真实采样间隔分别说明 | 每 5 秒抓取新样本；精确证明短暂事件的因果先后 |

## 审核一句话的方法

1. **是谁做的？** 上游业务样例与本人运维工作分开归属。
2. **验证了哪一层？** Running、Ready、Service 与业务数据分别给证据。
3. **范围是什么？** 标出环境、负载、时间窗口；演练说明故障模型。
4. **链接证明什么？** 配置证明设计，观测证明当时行为；哈希不能替代原始内容。
5. **还有什么未确定？** 用“未验证／未确定”保留空白，不用推测填补。

Stage 7 完整原始日志保留在原执行工作区，GitHub 公开的是报告、登记表、汇总及哈希索引。无法取得原归档时，说明审计限制；不声称所有原始数据可公开下载。Stage 8 只包装已有证据，不依赖启动 VM。
