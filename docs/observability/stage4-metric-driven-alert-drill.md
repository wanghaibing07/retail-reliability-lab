# Stage 4：Retail UI 指标驱动邮件演练（2026-09-24）

时区：北京时间 UTC+08:00。现场数据来自用户终端输出和收件确认；Git 合并时刻来自 GitHub。未采集精确指标首次失败和邮件送达时刻，不计算平均检测/恢复时间。

## 故障模型与边界

在不改变 Retail UI 的前提下，临时让 Blackbox 的 `http_200` 模块只接受 HTTP 418。UI 实际返回 HTTP 200，故 `up=1` 且 `probe_success=0`；测试的是探测判据驱动的规则与通知链路，**不代表真实业务停机**。

## 时间线与证据

| 北京时间 | 来源 | 观察或动作 |
| --- | --- | --- |
| 15:44:45 | 用户现场摘要 | `up=1`、`probe_success=1`、HTTP 200；规则 `ok/inactive`。 |
| 15:46:02 | [PR #33](https://github.com/wanghaibing07/retail-reliability-lab/pull/33) | 注入提交 `a9fb574ee76ee540e5f1519b8b1d3e7724791cc5` 合并；仅 `blackbox.yml` 的接受码 200→418。 |
| 15:50:25 | 用户终端原始输出 | Argo 对齐 `a9fb574`、Synced/Healthy；`up=1`、`probe_success=0`、HTTP 200；`RetailUIProbeFailed` 为 `ok/firing`。 |
| 15:50:59 | [PR #34](https://github.com/wanghaibing07/retail-reliability-lab/pull/34) | 恢复提交 `4eb6cb445b232e67455f28b16c57ec64c8455854` 合并，接受码恢复为 200。Git 文件树与注入前相同。 |
| 15:53:37 | 用户终端原始输出 | Argo 对齐 `4eb6cb4`、Synced/Healthy；`up=1`、`probe_success=1`；过去 15 分钟 `probe_success` 最小值 0，`ALERTS` 的 pending/firing 两阶段均可查到。 |
| 约 15:55 前 | 用户收件确认 | 收到 `RetailUIProbeFailed` 的 firing 邮件；准确发件/收件时间未提供。 |
| 恢复后，具体到达时间未提供 | 用户收件确认与规则状态 | 同一告警的邮件标题包含 `RESOLVED`；规则 `ok/inactive`。 |

## 验收结论

- **已通过：**探测指标失败 → 规则 pending/firing → 经 Alertmanager 到触发邮件；Git 恢复 → 探测成功、规则 ok/inactive → 同一告警的 RESOLVED 邮件。触发和恢复收件均由用户在本次演练中确认。
- **最终配置：**恢复提交合并后，Git 文件树与注入前相同；Argo 已在 15:53:37 到达恢复 revision。
- **限制：**这是判据故障；没有测真实 UI 宕机、数据库交易、全集群失联通知或各分支同时失效。

本次结束后关闭 S4-B；不再注入同一故障。阶段 4 的资源、保留与诊断覆盖仍继续实施。
