---
name: ai-worklog
description: 跨机器统计 Codex、Claude Code/CLI 等 AI 协作记录并生成工作日报、报工摘要和耗时表。Use when the user asks to summarize today/yesterday/a date's AI work, AI conversations, Codex/Claude sessions, tool calls, commits, files changed, or wants a reusable daily AI worklog/reporting workflow.
---

# AI Worklog

## 渐进式对话硬规则

这是面向大模型调用的 skill，默认不要让用户执行命令行。模型应该自己按阶段调用脚本。

1. 用户请求统计 AI 工作日报时，必须先生成 preview，不得直接生成正式 Excel。
2. preview 阶段只展示统计摘要和风险概览，不要在对话中展示完整原文、prompt、token、cookie、DSN 或私密内容。
3. 高风险记录默认不纳入。正式 Excel 只能基于 preview 中 `是否纳入=是` 的记录生成。
4. 用户说“按默认策略生成”或“我改完了”后，才能读取 preview 生成正式 Excel。
5. 用户说“只统计 XXX”时，将 XXX 转成 `--include-keyword XXX` 重新生成 preview。
6. 用户说“排除 XXX”时，按语义转成 `--exclude-keyword`、`--exclude-tool` 或 `--exclude-time` 重新生成 preview。
7. 用户说“全部都要我确认”时，使用 `--policy review_all` 重新生成 preview。
8. 生成正式 Excel 后，必须回报纳入记录数、排除记录数、高风险纳入数和文件路径。

## 对话状态机

- Idle：用户尚未发起日报请求。收到请求后先生成 preview。
- PreviewGenerated：已生成 `data/ai_worklog_preview.xlsx` 和 `data/ai_worklog_state.local.json`，等待用户确认。
- Confirmed：用户已确认默认策略或已手工改完 preview。读取 preview 并生成正式 Excel。
- FinalGenerated：正式 Excel 已生成。如用户继续说“排除 XXX 重新生成”，回到 PreviewGenerated。

## 自然语言到脚本参数的映射

| 用户说法 | 模型动作 |
| --- | --- |
| 帮我整理今天 AI 工作日报 | `--date today --preview` |
| 按默认策略生成 | `--from-state --excel` |
| 我改完预览表了 | `--from-state --excel` |
| 只统计 du_su_hou | `--preview --include-keyword du_su_hou` |
| 排除 Claude | `--preview --exclude-tool Claude` |
| 排除 12:00-14:00 | `--preview --exclude-time 12:00-14:00` |
| 排除工资、绩效 | `--preview --exclude-keyword 工资 --exclude-keyword 绩效` |
| 全部都要我确认 | `--preview --policy review_all` |

## 目标

把一天内使用 AI 完成的工作整理成可审计日报。优先读取本机可验证记录，不凭空补全。

适用请求示例：

- “总结我今天使用 AI 完成了什么”
- “统计昨天 Codex 和 Claude 的工作内容和耗时”
- “生成 2026-05-29 的 AI 报工表格”
- “把今天 AI 做的事按任务、耗时、交付结果整理出来”

## 执行入口

优先运行脚本生成结构化证据，再由 agent 汇总成表格：

```bash
python scripts/ai_worklog_collect.py --date today --format markdown
python scripts/ai_worklog_collect.py --date 2026-05-29 --format json
python scripts/ai_worklog_collect.py --date yesterday --root . --repo . --format markdown
python scripts/ai_worklog_collect.py --date today --preview
python scripts/ai_worklog_collect.py --date today --from-preview data/ai_worklog_preview.xlsx --excel --format markdown
```

Excel 台账写入：

预览确认流程：

1. 先运行 `--preview` 生成 `data/ai_worklog_preview.xlsx`，只输出候选素材清单，不生成正式日报。
2. 用户打开预览 Excel，在 `是否纳入` 列修改 `是/否`。
3. 再运行 `--from-preview <path> --excel`，脚本只基于用户确认为 `是` 的记录生成正式 Excel。
4. `data/privacy_config.local.jsonc` 会自动生成，内含中文注释，可自行修改黑名单、白名单、排除时间段和默认纳入策略。
5. `data/*.xlsx` 和 `data/*.local.jsonc` 都是本地文件，不提交 Git。


- 使用 `--excel` 时，默认写入 `data/ai_worklog.xlsx`。
- 使用 `--excel <path>` 可以指定台账路径。
- 默认 `--excel-mode upsert` 会先删除同一日期旧行再写入，避免重复追加。
- 使用 `--excel-mode append` 可保留历史重复运行记录。
- `data/*.xlsx` 属于本地报工台账，不提交 Git。脚本只落地 Excel，不保留中间 JSON。

脚本输出只用于辅助统计。最终日报仍需由 agent 检查和归并任务，避免把系统消息、授权等待、工具中断误算成工作。

从 Git 安装后的 `data/` 目录不会包含任何样例日报或个人 Excel。正式 Excel 由本机 preview 确认后的记录生成；如果用户或模型直接调用脚本写 Excel，脚本会自动生成一版中文报工兜底文案，但更精细的任务归并和业务价值润色仍应由 agent 基于明细页完成。

## 路径发现规则

不得写死个人目录。按以下顺序自动发现：

1. Codex：`CODEX_HOME`，否则 `~/.codex`。
2. Claude：`CLAUDE_CONFIG_DIR`，否则 `~/.claude`。
3. 当前工作目录及 `--root`、`--repo` 指定的目录。
4. 对 git 仓库，只检查用户指定目录和 AI session 中出现过的工作目录。

Windows、macOS、Linux 都使用 `Path.home()` 和环境变量解析路径。

## 标准流程

1. 确定日期。
   - 用户未指定时使用本地时区今天。
   - 用户指定 `today`、`yesterday` 或 `YYYY-MM-DD` 时按本地时区处理。
2. 收集记录。
   - Codex：读取 `sessions/YYYY/MM/DD/*.jsonl`。
   - Claude：读取 `history.jsonl`、`projects/**/*.jsonl`、`sessions/*.json`。
   - Git：读取相关仓库当天 commit、当前 status。
   - 文件：仅汇总 AI 记录中出现的文件、生成物、skill/plugin 安装痕迹。
3. 解析对话。
   - 提取用户请求、assistant 最终回复、工具调用、开始/结束时间。
   - 忽略系统提示、skill 全文加载、权限列表、纯 telemetry。
4. 归并任务。
   - 相邻且目标一致的对话合并为一个任务。
   - 不同系统、接口、仓库、文档主题应拆开。
5. 估算耗时。
   - AI 活跃耗时：用户请求到 task_complete/end_turn/最后 assistant 回复。
   - 超过 30 分钟且中间无工具调用或消息时，标记为自然空档，不直接算满。
   - 真实工作耗时默认按 AI 活跃耗时乘 3，再按任务类型校正。
6. 脱敏。
   - 不输出 token、password、cookie、完整 DSN、授权码、私钥。
   - 涉及敏感内容只写“已脱敏”。
7. 输出 Excel：前 3 张为日报总览、周汇总、月汇总，后 7 张为明细页，任务表包含证据强度。

## 输出格式

Excel 台账固定写入 10 个中文工作表，不保留中间 JSON。

前 3 张是汇总页：

- 日报总览：日期、AI活跃耗时、估算真实工作耗时、任务数、Git提交数、状态数量、证据强度数量、主要项目。
- 周汇总：按 ISO 周汇总耗时、任务数、Git 提交数、状态数量和证据强度。
- 月汇总：按月汇总同样指标，用于月度报工和复盘。

后 7 张是明细页：

- 数据来源检查
- AI 对话明细
- 任务归并统计（包含证据强度）
- 证据汇总
- 耗时汇总
- 今日完成事项摘要
- 可直接报工版本

证据强度规则：

- 强：有 commit、文件改动、session 等可交叉验证证据。
- 中：有 session、SQL、PG 查询、本地文件或工具调用证据。
- 弱：只有对话性分析，缺少可交叉验证证据。

## 任务类型和估时系数

| 类型 | 默认系数 |
| --- | ---: |
| 简单问答/总结 | 2.0 |
| 文档/飞书/表格分析 | 2.5 |
| SQL/数据库验证 | 3.0 |
| Bug 排查 | 3.0 |
| 代码开发/提交 | 3.5 |
| 跨系统方案/业务沟通 | 4.0 |
| 自动化工具/skill 建设 | 3.5 |

## 安全规则

- 只读扫描日志、session、git 和文件元数据。
- 不删除、不移动、不覆盖用户文件。
- 不自动提交、不自动推送。
- 不把敏感信息写入最终报告。
- 如果记录缺失，明确写“未发现可归因记录”。

## 参考资料

- 详细解析策略：`references/parsing_strategy.md`
