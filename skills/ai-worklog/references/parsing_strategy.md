# 解析策略

## Codex

优先扫描 `sessions/**/*.jsonl` 中“创建日期不晚于目标日期、最后写入时间覆盖目标日期”的候选文件，再按每条消息 timestamp 精确筛选目标日期。这样可以覆盖前一天创建、当天继续工作的旧对话。

关键记录：

- `session_meta.payload.cwd`：工作目录。
- `event_msg/user_message`：用户请求。
- `event_msg/agent_message`：中间或最终说明。
- `event_msg/task_complete`：任务完成时间。
- `response_item/function_call`：工具调用。
- `response_item/function_call_output`：工具输出。

统计规则：用户消息到最近的 `task_complete` 算一轮 AI 活跃耗时。若没有 `task_complete`，用最后一条 assistant/tool 时间作为估算结束。跨日时只截取目标日期内的轮次，不把次日回复拉长到前一天。

## Claude Code / CLI

优先读取：

- `history.jsonl`：入口请求索引。
- `projects/**/*.jsonl`：完整项目会话。候选文件按最后写入时间覆盖目标日期筛选，文件内部仍按 timestamp 精确筛选目标日期。
- `sessions/*.json`：会话元数据。

关键记录：

- `type=user` 且 `message.role=user`：用户请求或工具结果。
- `type=assistant`：assistant 回复和工具调用。
- `type=system, subtype=turn_duration`：Claude 轮次耗时。

过滤规则：忽略 `tool_result`、skill 全文注入、权限列表、系统 recap。只统计真实用户输入。

## Git

默认只检查相关仓库：

- 当前目录。
- `--repo` 指定目录。
- AI session 中出现过的 `cwd`。

`--root` 只用于辅助定位当前目录或会话 cwd 所属仓库，不默认扫描其下所有 Git 仓库，避免把无关项目的大量未提交文件写进日报。

记录当天 commit、当前 status 摘要。不要把未关联的大量历史 untracked 文件当作当天 AI 产出，除非 session 证据指向它们。

## 耗时口径

- AI 净活跃耗时：逐轮用户请求到 AI 完成回复/工具调用的时间相加。
- 连续协作窗口耗时：相邻 AI 轮次间隔不超过 30 分钟时合并，用于表达真实协作窗口。
- 建议报工耗时：按任务类型对 AI 净活跃耗时乘以系数后得到。

## 脱敏

最终报告禁止输出：

- password、token、secret、cookie、authorization、private key。
- 完整数据库 DSN。
- OAuth code、refresh token、access token。

命中敏感字段时替换为 `[REDACTED]`。
