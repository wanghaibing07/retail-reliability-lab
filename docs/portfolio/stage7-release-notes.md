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

Stage 7 性能与容量验证封板：基于 AWS Retail Store Sample App 的三节点 Kubernetes 可靠性工程实验室。

> **最新补充说明**：以下为 stage7-v0.8 tag 初始发布留档；后续补充的高分辨率阶梯实验（E19–E21）已成功闭环：**39 RPS（13 VU/s）验证全绿**；**42 RPS（14 VU/s）精准锁定饱和拐点**（MySQL CPU 触顶 0.75 核引发排队雪崩），系统容量拐点已精确锁定在 39～42 RPS。最新报告见 [Stage 7 性能测试报告](../performance/stage7-closeout.md)。

- **已验证健康运行点**：30 RPS 基准健康稳态通过；后续 E19/E20 进一步将安全稳态上限验证至 **39 RPS / 300 秒（13 VU/s）**，33,750 请求 100% 成功。
- **容量拐点与崩溃阈值**：**42 RPS（14 VU/s）** 触发展开排队与并发池耗尽，吞吐骤降，精准锁定系统容量拐点；**45 RPS** 多轮出现严重不可服务级退化与连接拒绝。
- **历史探索样本资格**：早期 E16/E17 因缺少后置指标或预热中断严格判定为 INVALID（无效），不采纳为正式结论，促成了后续高规范的 E19–E21 验证。
- **S7-F 未新增被测系统优化**：容量基线测定阶段未做系统参数微调，此前 UI 异步修复仍属于本次测试基线。
- **只封板文档与证据**：不承诺生产容量、生产级高可用或完整灾备。

[封板报告](https://github.com/wanghaibing07/retail-reliability-lab/blob/stage7-v0.8/docs/performance/stage7-closeout.md) · [证据索引](https://github.com/wanghaibing07/retail-reliability-lab/blob/stage7-v0.8/evidence/stage7/README.md) · [实验登记表](https://github.com/wanghaibing07/retail-reliability-lab/blob/stage7-v0.8/evidence/stage7/experiment-register.csv)

公开索引包含摘要和归档校验值。完整原始日志保留在原执行工作区，未打包进本 Release。

## 发布后核验结果

页面显示 `stage7-v0.8` 与提交 `0fa9720`；GitHub API 确认非草稿、非 prerelease。正文与上方入库稿逐字一致（仅统一 CRLF/LF 换行），tag 对象与 target 保持原值。S8-H 的 Release 展示已完成，Stage 7 技术结论未改变。

机制依据：[GitHub 官方：管理 Release，选择现有 tag](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)。
