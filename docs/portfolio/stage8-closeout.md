# Stage 8 Portfolio / Interview Packaging 验收

**结论：Stage 8 交付材料完成。** 2026-10-06，将既有 Stage 0～7 记录压缩为招聘入口、项目表达、面试追问与证据边界。完成的是作品集材料交付，不宣称本人已经排练熟练或获得招聘结果。

## 八项验收

| 项目 | 状态 | 可审阅交付 |
| --- | --- | --- |
| S8-A：30 秒 README | COMPLETE | [项目定位、关键结果与证据入口](../../README.md#30-秒看懂这个项目)，Stage 7/8 状态与历史快照口径已统一 |
| S8-B：架构图 | COMPLETE | [交付/监控主图、业务依赖与恢复路径](architecture.md)，使用仓库内 Mermaid，不依赖在线 Lab |
| S8-C：五个故事 | COMPLETE | [五个工程与排障故事](incident-stories.md)，区分真实 Incident、主动演练和风险整改 |
| S8-D：分层讲解 | COMPLETE | [60 秒](architecture.md#60-秒讲解)及 [3 分钟 / 10 分钟](interview-guide.md)讲稿，含被打断后的转向提示 |
| S8-E：简历条目 | COMPLETE | [五条成果与按岗位选择方法](resume-bullets.md)，每条有证据与数字边界 |
| S8-F：项目题库 | COMPLETE | [24 题、12 道优先题](interview-question-bank.md)，折叠短答、项目证据与下一层追问 |
| S8-G：声明边界 | COMPLETE | [统一边界表](claim-boundaries.md)，保留有效/无效资格、统计窗口与未确定项 |
| S8-H：Release / 仓库展示 | COMPLETE | [stage7-v0.8 Release](https://github.com/wanghaibing07/retail-reliability-lab/releases/tag/stage7-v0.8)、[发布核验](stage7-release-notes.md)，README 直接链接全部求职材料，项目已固定到 [个人主页](https://github.com/wanghaibing07) |

## 变更与验证记录

- [PR #58](https://github.com/wanghaibing07/retail-reliability-lab/pull/58)：README 入口、进度纠正与架构；已合并。
- [PR #59](https://github.com/wanghaibing07/retail-reliability-lab/pull/59)：简历条目、分层讲稿与五个故事；已合并。
- [PR #60](https://github.com/wanghaibing07/retail-reliability-lab/pull/60)：题库、统一边界与 Release 正文；已合并。README 与作品集文档的 180 个本地链接/锚点及 24 个折叠问答通过检查。
- 本次收尾提交更新完成状态与本验收索引，经静态检查、PR CI 和合并后 main CI 验收；具体提交与运行结果从本文件 Git 历史及 Actions 对应提交核对，不在文档中预写尚未生成的合并 SHA。
- GitHub Release 实际发布时间：2026-10-06 22:49:48（Asia/Shanghai）。页面与 API 确认已发布；正文与入库说明一致。
- GitHub 个人主页已将 retail-reliability-lab 设为 Pinned，页面显示保存成功。

Stage 8 仅修改展示文档并发布现存 tag 的 Release。Stage 7 closeout、实验登记表和证据索引保持原样；`stage7-v0.8` annotated tag 对象仍为 `1fa73f104040dec7885e63105d61a3ec2e0f3179`，target 仍为 `0fa9720338d553ab9cd815e7cc79ebea42f178e2`。未启动 VM、未运行新容量实验、未新增 SUT 优化。作品集完成通过本次 PR 和 main 记录，无需另建 portfolio tag。

## 怎样使用这些材料

1. **投递：** 按目标岗位选择三到五条简历描述，把 README 作为项目链接。
2. **面试开场：** 脱稿说明 60 秒版本，用架构图回答“自己做了什么”。
3. **深入追问：** 选择一个故事讲清问题、动作、证据和结果，再用题库找遗漏。
4. **核验措辞：** 数字、容量、恢复及故障归因先核对声明边界，原记录优先。

材料时长是排练目标，实际表达能力需要本人练习；这与文档交付验收分开。不为展示引入新组件或重新开放 Stage 7。
