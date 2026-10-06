# Stage 7 GitHub Release 发布说明

状态：说明已准备，尚未发布 GitHub Release 页面。Git tag 已存在，Stage 7 release acceptance 已成立；GitHub 页面属于 Stage 8 展示工作。

| 发布字段 | 固定值 |
| --- | --- |
| Existing tag | `stage7-v0.8` |
| Title | `Stage 7 Performance / Capacity Closeout` |
| Tag target | `0fa9720338d553ab9cd815e7cc79ebea42f178e2` |
| 发布范围 | 已封板报告与证据索引，不含新实验或优化 |

发布时选择现存 tag，不创建新 tag、不移动 target。下面正文只链接该 tag 的内容，避免把后续 main 的文档包装误当成 Stage 7 发布文件。不额外上传缺失的原始日志或编造附件。

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

## 发布后核验

核对 Release 页面使用 `stage7-v0.8`，tag 仍指向上述提交，正文与本稿一致；记录页面链接。页面实际发布前，README 的 Stage 8 状态保持进行中，不把 S8-H 宣布完成。

机制依据：[GitHub 官方：管理 Release，选择现有 tag](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。
