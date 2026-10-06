# Stage 7 GitHub Release 发布说明

> 中文阅读入口：[先用中文看懂项目与术语](plain-language-guide.md)。工具名称、命令和正式状态字段保留原文，便于核对证据。

状态：已发布 [GitHub Release 页面](https://github.com/wanghaibing07/retail-reliability-lab/releases/tag/stage7-v0.8)。发布时间为 2026-10-06 22:49:48（Asia/Shanghai，UTC 14:49:48），Release ID 为 `404844004`，draft=false、prerelease=false。Git tag 原已存在，Stage 7 release acceptance 原已成立；本次页面发布属于 Stage 8 展示工作。

| 发布字段 | 固定值 |
| --- | --- |
| Existing tag | `stage7-v0.8` |
| Title | `Stage 7 性能与容量验证封板` |
| Tag target | `0fa9720338d553ab9cd815e7cc79ebea42f178e2` |
| 发布范围 | 已封板报告与证据索引，不含新实验或优化 |

本次发布选择现存 tag，未创建新 tag、未移动 target。下面正文只链接该 tag 的内容，避免把后续 main 的文档包装误当成 Stage 7 发布文件。未额外上传原始日志；页面的两个 Source code 压缩包是 GitHub 自动提供的 tag 源码归档。

## Release 正文（中文）

Stage 7 性能与容量验证封板：基于 AWS Retail Store Sample App 的本地三节点 Kubernetes 运维与可靠性实验室。

- **已验证健康运行点：30 RPS / 300 秒**，即固定只读浏览负载下，每秒约 30 个 HTTP 请求持续 300 秒。
- **45 RPS 多轮出现阶段性退化**：出现超时或延迟突增，后段恢复；不能称为硬上限或最大容量。
- **39 RPS 尚无有效资格结论**：E16/E17 为 INVALID（无效）；E17 正式实验未测；E18 为 NOT_STARTED（尚未开始的生命周期状态），正式结果 N/A。
- **精确性能拐点与最大容量尚未确定**。30～45 RPS 是已测的调查范围，不是数学证明的精确拐点区间。
- **S7-F 未新增被测系统优化**：因果证据不足；此前 UI 异步修复仍属于本次测试基线。
- **只封板文档与证据**：不承诺生产容量、生产级高可用或完整灾备。

[封板报告](https://github.com/wanghaibing07/retail-reliability-lab/blob/stage7-v0.8/docs/performance/stage7-closeout.md) · [证据索引](https://github.com/wanghaibing07/retail-reliability-lab/blob/stage7-v0.8/evidence/stage7/README.md) · [实验登记表](https://github.com/wanghaibing07/retail-reliability-lab/blob/stage7-v0.8/evidence/stage7/experiment-register.csv)

公开索引包含摘要和归档校验值。完整原始日志保留在原执行工作区，未打包进本 Release。

## 发布后核验结果

页面显示 `stage7-v0.8` 与提交 `0fa9720`；GitHub API 确认非草稿、非 prerelease。正文与上方入库稿逐字一致（仅统一 CRLF/LF 换行），tag 对象与 target 保持原值。S8-H 的 Release 展示已完成，Stage 7 技术结论未改变。

机制依据：[GitHub 官方：管理 Release，选择现有 tag](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。
