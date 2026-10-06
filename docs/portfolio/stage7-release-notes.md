# Stage 7 GitHub Release 发布说明

状态：已发布 [GitHub Release 页面](https://github.com/wanghaibing07/retail-reliability-lab/releases/tag/stage7-v0.8)。发布时间为 2026-10-06 22:49:48（Asia/Shanghai，UTC 14:49:48），Release ID 为 `404844004`，draft=false、prerelease=false。Git tag 原已存在，Stage 7 release acceptance 原已成立；本次页面发布属于 Stage 8 展示工作。

| 发布字段 | 固定值 |
| --- | --- |
| Existing tag | `stage7-v0.8` |
| Title | `Stage 7 Performance / Capacity Closeout` |
| Tag target | `0fa9720338d553ab9cd815e7cc79ebea42f178e2` |
| 发布范围 | 已封板报告与证据索引，不含新实验或优化 |

本次发布选择现存 tag，未创建新 tag、未移动 target。下面正文只链接该 tag 的内容，避免把后续 main 的文档包装误当成 Stage 7 发布文件。未额外上传原始日志；页面的两个 Source code 压缩包是 GitHub 自动提供的 tag 源码归档。

## Release body

Stage 7 Performance / Capacity Closeout for the local three-node Retail Reliability Lab, based on AWS Retail Store Sample App.

- Proven healthy: **30 RPS / 300s**, under the fixed read-only browse workload.
- Repeatable **episodic degradation observed at 45 RPS**, with later recovery; not a hard ceiling.
- **39 RPS inconclusive**: E16/E17 INVALID; E17 formal NOT TESTED; E18 NOT_STARTED (lifecycle), formal N/A.
- **Exact knee / maximum capacity unresolved**. 30–45 RPS is the tested investigation envelope, not a proven exact knee bracket.
- **No new SUT optimization** in S7-F due to insufficient causal evidence; the prior UI async fix remains part of the tested baseline.
- **Documentation/evidence closeout only**. No production capacity, HA or DR guarantee.

[Closeout report](https://github.com/wanghaibing07/retail-reliability-lab/blob/stage7-v0.8/docs/performance/stage7-closeout.md) · [Evidence index](https://github.com/wanghaibing07/retail-reliability-lab/blob/stage7-v0.8/evidence/stage7/README.md) · [Experiment register](https://github.com/wanghaibing07/retail-reliability-lab/blob/stage7-v0.8/evidence/stage7/experiment-register.csv)

The public index contains summaries and archive hashes. Full raw logs remain in the original execution workspace and are not bundled in this Release.

## 发布后核验结果

页面显示 `stage7-v0.8` 与提交 `0fa9720`；GitHub API 确认非草稿、非 prerelease。正文与上方入库稿逐字一致（仅统一 CRLF/LF 换行），tag 对象与 target 保持原值。S8-H 的 Release 展示已完成，Stage 7 技术结论未改变。

机制依据：[GitHub 官方：管理 Release，选择现有 tag](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。
