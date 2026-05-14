# Feishu/Lark 安全策略

## 敏感信息

- 不要把 `app secret`、`access token`、`refresh token`、cookie、密码写入 skill、仓库、文档或最终回复。
- 命令输出包含敏感值时，只报告状态，并对敏感值脱敏。
- 默认使用 `--as user` 执行 document/wiki/sheet 操作。

## 高风险操作

以下操作必须先做只读目标验证，再等待使用者明确确认：

- delete
- move
- permission transfer
- permission delete
- batch write
- batch update
- `docs +update --mode overwrite`
- 清空内容或替换整篇文档

确认前必须告知：

- 目标对象，例如 `doc_token`、URL、title、`wiki_node_token`。
- 操作类型。
- 影响范围。
- 是否可恢复。
- 执行后的验证方式。

## 行为边界

- 使用者只要求查看、读取、检查时，不得升级为写入、覆盖、删除或权限变更。
- 如果功能不支持，先检索处理方式和 CLI/schema/help，不要编造能力。
- 新处理方式验证成功后，应沉淀回 skill 的 scripts 或 references。
