---
name: lark-cli-config
description: Use before any Feishu/Lark document, wiki, sheet, drive, or lark-cli operation. This skill guides lark-cli environment checks, user authorization, scope recovery, safe document fetch/create/update workflows, high-risk operation confirmation, and iterative skill improvement when a requested Feishu capability is not yet supported.
metadata:
  short-description: Step-by-step lark-cli authorization guide
---

# Lark CLI Config

## 触发规则

遇到 Feishu/Lark document、wiki、sheet、drive、base、bitable、权限、授权、`lark-cli` 相关任务时，先使用这个 skill。

典型场景：
- 读取、fetch、创建、更新、覆盖、发布 Feishu document/wiki。
- 读取或写入 sheet/base/bitable。
- 处理 Feishu 链接、`doc_token`、`wiki_node_token`、`spreadsheet_token`。
- 排查 `lark-cli`、scope、authorization URL、`user token`、`bot identity`、`device login`。
- 其他 skill 准备同步飞书文档前。

## 执行入口

优先使用脚本，避免把执行细节塞入上下文：

- 环境诊断：`python scripts/env_diagnostics.py`
- 授权状态：`python scripts/auth_manager.py status`
- 引导登录：`python scripts/auth_manager.py login --domain docs,wiki,drive`
- 登出：`python scripts/auth_manager.py logout`
- 文档操作：`python scripts/doc_ops_wrapper.py preflight|execute --operation <operation> ...`

所有脚本输出 JSON。Agent 应读取 JSON 的 `ok`、`next_action`、`requires_confirmation`、`risk`、`message` 字段决定下一步。

## 规则导航

按需读取这些 reference，不要默认整篇加载：

- scope 映射：`references/scopes.json`
- 安全规则：`references/security_policy.md`
- Windows 中文上传：`references/windows_encoding_guide.md`
- 常见错误处理：`references/lark_cli_error_map.md`
- 操作风险矩阵：`references/operation_risk_matrix.json`

## 标准流程

1. 运行 `scripts/env_diagnostics.py`，确认 `lark-cli` 可用。
2. 运行 `scripts/auth_manager.py status`，确认 `identity` 和 `tokenStatus`。
3. 如果没有 `user` 授权，运行 `scripts/auth_manager.py login --domain docs,wiki,drive`，引导使用者完成浏览器授权。
4. 读取类操作可用 `doc_ops_wrapper.py execute --operation docs_fetch` 直接执行。
5. 写入、覆盖、移动、删除、权限变更先运行 `doc_ops_wrapper.py preflight`。
6. 如果返回 `requires_confirmation: true`，必须向使用者展示目标、风险、影响和验证方式，等待明确确认后才能执行 `--confirmed`。
7. 写入后必须执行 fetch/read 验证。

## 不支持功能时的处理规则

当使用者需要的 Feishu 功能当前脚本或 skill 不支持时：

1. 不要直接拒绝，也不要编造能力。
2. 先检索可行处理方式：优先查 `lark-cli <command> --help`、`lark-cli schema ...`、本 skill references、已安装 lark-cli 能力；必要时查询官方文档或公开实现。
3. 先用只读命令或 `--dry-run` 验证方案可行性。
4. 引导使用者完成当前任务；高风险操作仍按安全确认流程执行。
5. 任务完成后，把可复用经验沉淀回本 skill：更新脚本、references 或 `SKILL.md` 导航，并运行 `quick_validate.py`。

## 安全底线

- 命令、参数、scope、JSON 字段、文件名保持英文；说明和引导使用中文。
- 不保存或泄露 `app secret`、`access token`、`refresh token`、cookie、密码。
- 默认优先 `--as user`。
- delete、move、permission transfer、permission delete、batch write、`docs +update --mode overwrite` 等高风险操作必须先确认。
- 用户只要求查看或读取时，不得升级为写入、覆盖、删除或权限变更。

## 最终反馈

完成后只报告：
- `lark-cli` 可用状态。
- `auth identity`：`user`、`bot` 或 `auto`。
- `tokenStatus` 和 `expiresAt`。
- 已验证的 command 或 operation。
- 高风险操作的确认与验证结果。
- 剩余 blocker 或已沉淀的 skill 优化项。

