---
name: git-trunk-workflow
description: Manage AI-assisted short-lived Git delivery branches inspired by Trunk-Based Development and adapted for dev/uat/release/prod workflows. Use when the user asks to create an ai/* temporary branch from a source branch, sync the source before branching, inspect Git state, protect user changes, stage current-task files only, write detailed Chinese commits, push AI temporary branches, summarize validation evidence, check merge/backport targets, or produce merge handoff notes. Does not merge long-lived branches, deploy, force push, discard changes, or run destructive Git operations.
---

# Git Trunk Workflow

## 定位

用于 AI 协作开发中的短生命周期 Git 分支交付流程。它借鉴 Trunk-Based Development 的短分支、小提交、快速回灌原则，但适配存量项目常见的 `dev` / `uat` / `release` / `prod` 多环境分支。

本 Skill 负责从明确来源分支迁出 `ai/*` 临时分支、保护用户已有改动、提交本次任务、可选 push 远程临时分支、收口验证事实并输出合并前交接。它不负责合并长期分支，也不负责部署。

## 核心原则

- 明确来源分支：每次创建 AI 临时分支前确认来源是 `dev`、`uat`、`release/*`、`prod` 或当前问题分支。
- 迁出前同步：优先 `fetch`，仅在工作区干净、位于来源分支、且可 fast-forward 时执行 `pull --ff-only`。
- 短生命周期：一个 `ai/*` 分支只处理一个需求、bug、UAT 修复或线上问题。
- 小范围提交：只提交本次任务相关文件，不混入用户已有改动、无关格式化或顺手重构。
- 中文详细 commit：提交信息用中文写清背景、修改、验证、影响；复杂任务允许多个 commit。
- 远程可 review：允许 push `ai/*` 分支到远程，用于 review、CI 或跨机器同步。
- 人控合并部署：最终合回 `dev` / `uat` / `main` / `master` / `release` 以及部署上线由用户完成。
- 白名单脚本：优先使用本 Skill 的脚本执行安全 Git 操作，脚本拒绝风险动作。

## 分支命名

默认分支格式：

```text
ai/<source>/<yyyymmdd>-<type>-<short-topic>
```

示例：

```text
ai/uat/20260608-fix-export-null
ai/dev/20260608-feat-shop-filter
ai/release-202606/20260608-hotfix-price-sync
ai/prod/20260608-hotfix-login-npe
```

规则：

- `ai` 表示 AI 临时交付分支。
- `<source>` 写迁出来源分支；如果来源包含 `/`，在分支名中转换为 `-`，例如 `release/202606` 写作 `release-202606`。
- `<type>` 推荐使用 `fix`、`feat`、`bug`、`hotfix`、`docs`、`chore`、`refactor`。
- 分支名使用英文、数字和短横线；中文细节写进 commit 和交接摘要。
- 有需求号或缺陷号时可写入 topic，例如 `ai/uat/20260608-bug-OTB-1234-export-null`。

## 安全底线

禁止默认执行：

- 合并到 `dev`、`uat`、`main`、`master`、`release/*` 等长期分支。
- 部署或发布。
- `git reset --hard`。
- `git clean -fd`。
- `git checkout -- <path>` 或任何丢弃用户改动的动作。
- `git push --force` 或等价强推。
- 删除本地/远程分支。
- 删除 tag。
- 未授权 rebase、amend、squash、cherry-pick。
- 盲目 `git add .`。

执行任何 branching、staging、commit、push 前，必须先检查仓库状态并区分本次任务变更与疑似无关变更。

## 标准流程

### 1. Preflight 检查

先运行只读检查，推荐脚本：

```powershell
.\skills\git-trunk-workflow\scripts\git_preflight.ps1 -Fetch
```

需要确认：

- 仓库根目录。
- 当前分支。
- 当前 upstream。
- ahead / behind 状态。
- staged、unstaged、untracked 文件。
- 是否已有 `ai/*` 分支。
- 是否处于 rebase、merge、cherry-pick 等中间状态。

如果工作区不干净，不要自动 pull 或切换分支。先判断改动归属，并提示用户确认。

### 2. 来源分支同步

迁出前优先让来源分支接近远端最新状态，但只允许安全同步：

- 先执行 `git fetch origin --prune`。
- 当前位于来源分支且工作区干净时，允许 `git pull --ff-only`。
- `pull --ff-only` 失败时停止；不自动 merge、不自动 rebase。
- 当前不在来源分支时，不自动切换；除非用户明确要求切换。
- 无法同步时，可以基于当前本地基线创建，但交接单必须标注“基线未同步”。

推荐脚本：

```powershell
.\skills\git-trunk-workflow\scripts\create_ai_branch.ps1 -SourceBranch uat -BranchName ai/uat/20260608-fix-export-null -SyncSource
```

### 3. 创建 AI 临时分支

创建前记录来源分支快照：

- 来源分支名。
- 来源本地 commit。
- 来源远端 commit，如果存在。
- 是否已 fetch。
- 是否执行并通过 `pull --ff-only`。

创建分支只允许 `ai/*` 名称，不覆盖已有分支。创建成功后最终回复中按 Codex 桌面规则输出 `::git-create-branch{...}`。

### 4. 开发期间边界检查

业务实现可以由普通 Codex 流程或其他专业 Skill 完成。本 Skill 负责交付边界：

- 开发前后对比变更文件。
- 按归属把文件分为：本次任务相关、疑似相关需确认、疑似无关默认排除。
- 文件内混杂多个任务时，建议用户用 Fork 图形客户端做 hunk 级审查或分块暂存。
- 不用交互式 `git add -p` 作为默认方案。

### 5. 验证收口

提交前后都要收集验证事实，不用空泛的“已验证”。记录：

- 单元测试命令和结果。
- 构建命令和结果。
- 接口或页面验证结果。
- 数据库只读验证 SQL 和结果。
- 日志验证结果。
- 未执行项及原因。

验证状态分级：

```text
Ready to merge: 关键测试/构建/目标效果验证通过，可建议合并。
Ready for review: 代码已提交，但验证不完整或存在待确认项，适合 review，不建议直接合并。
Blocked: 关键验证失败、构建失败或目标效果未证明，不建议合并。
```

### 6. 显式暂存

只暂存本次任务相关的显式路径，推荐脚本：

```powershell
.\skills\git-trunk-workflow\scripts\stage_paths.ps1 -Paths path1,path2
```

规则：

- 拒绝 `.`、`*`、`--all`、`-A` 等全量暂存表达。
- 暂存前展示文件列表。
- 疑似无关文件默认排除。
- 暂存成功后最终回复中按 Codex 桌面规则输出 `::git-stage{...}`。

### 7. 中文详细提交

推荐提交格式：

```text
<type>: <一句话说明>

- 背景：为什么要改
- 修改：具体改了哪些关键逻辑
- 验证：执行了哪些测试/数据验证
- 影响：影响范围和兼容性说明
```

示例：

```text
fix: 修复 UAT 导出字段为空导致报错

- 背景：UAT 导出历史数据时部分字段为空，触发接口异常
- 修改：补充字段空值兼容，并调整 Mapper 查询默认值处理
- 验证：已执行导出相关单测，并基于 UAT 现有数据验证目标场景
- 影响：仅影响导出接口的空值兜底逻辑，不改变正常数据路径
```

推荐脚本：

```powershell
.\skills\git-trunk-workflow\scripts\commit_cn.ps1 -Title "fix: 修复 UAT 导出字段为空导致报错" -Bullets "背景：...","修改：...","验证：...","影响：..."
```

复杂任务可以多 commit，例如修复、测试、文档拆开。提交成功后最终回复中按 Codex 桌面规则输出 `::git-commit{...}`。

### 8. 只 push AI 临时分支

push 是可选动作，必须由用户明确要求。推荐脚本：

```powershell
.\skills\git-trunk-workflow\scripts\push_ai_branch.ps1
```

规则：

- 只能 push 当前 `ai/*` 分支。
- 拒绝 push `dev`、`uat`、`main`、`master`、`release/*`、`prod` 等长期分支。
- 拒绝 force push。
- 默认使用 `git push -u origin <current-ai-branch>`。
- 不允许把 `ai/uat/...` 推送成远端 `dev` 或其他长期分支。
- push 成功后最终回复中按 Codex 桌面规则输出 `::git-push{...}`。

### 9. 目标分支差异和冲突预警

交接前做只读检查：

- 第一合并目标与 AI 分支的 diff stat。
- 回灌目标与 AI 分支涉及文件是否差异较大。
- 目标分支远端是否已有新提交。
- 是否建议 merge、cherry-pick 或从目标分支重新开 `ai/*` 分支适配。

不要为了测试冲突而直接 merge 长期分支。若需要冲突演练，只能建议在额外临时测试分支中完成，并由用户确认。

### 10. 合并前交接

每次 commit 或 push 后必须输出交接摘要。推荐先用脚本采集事实：

```powershell
.\skills\git-trunk-workflow\scripts\git_handoff_summary.ps1 -PrimaryTarget uat -BackportTarget dev
```

交接摘要必须包含：

```text
交付状态：Ready to merge / Ready for review / Blocked
来源分支：
来源 commit：
来源远端 commit：
迁出前是否 fetch：
迁出前是否 pull --ff-only：
AI 临时分支：
AI 分支 HEAD：
commit 列表：
是否已 push：
是否还有未提交改动：
本次任务相关文件：
疑似相关需确认文件：
疑似无关默认排除文件：
第一合并目标：
是否建议回灌：
回灌目标：
建议方式：merge / cherry-pick / 重新适配
验证结果：
合并前风险点：
发布注意事项：SQL / 配置 / 缓存 / 队列 / 模板
回滚建议：
建议清理时间：合并完成并确认回灌后 7-30 天
```

## 合并和回灌建议

根据来源分支给建议，不默认合并：

- 从 `dev` 迁出：第一合并目标通常是 `dev`。
- 从 `uat` 迁出：第一合并目标通常是 `uat`；通用缺陷建议回灌 `dev`。
- 从 `release/*` 或 `prod` 迁出：第一合并目标是对应 release/prod 分支；修复稳定后评估回灌 `uat` / `dev`。
- 分支差异小可建议 merge。
- 分支差异大优先建议 cherry-pick 修复 commit。
- 冲突风险高时建议从目标分支重新开 `ai/*` 分支适配修复。

## 未完成工作

不把 Feature Flag 作为硬要求。存量系统不适配时，不强行引入特性开关。

规则：

- 未完成工作可以留在 `ai/*` 临时分支。
- 未完成工作不建议合入目标长期分支。
- 如果必须合入，需要明确隔离方式并由用户确认。
- 隔离方式可以是配置开关、菜单隐藏、权限控制、接口不暴露、旧逻辑保留等，不限定标准 Feature Toggle。

## 远程分支生命周期

`ai/*` 分支可以远程 push，但需要定期清理：

- 已合并并确认回灌完成：建议 7-30 天后清理。
- 未合并且超过 30-60 天：提醒用户确认是否保留。
- 生产 hotfix：确认合入目标分支并回灌 `dev` / `uat` 后再清理。
- 本 Skill 默认不删除本地或远程分支，只输出清理建议。

## 脚本入口

脚本位于 `scripts/`；除公共 helper `git_common.ps1` 外，入口脚本都输出 JSON：

- `git_preflight.ps1`：检查仓库、分支、工作区、远端状态。
- `create_ai_branch.ps1`：安全同步来源分支并创建 `ai/*` 分支。
- `stage_paths.ps1`：只暂存显式文件路径。
- `commit_cn.ps1`：中文详细 commit，支持多 bullet。
- `push_ai_branch.ps1`：只 push 当前 `ai/*` 分支。
- `git_handoff_summary.ps1`：采集交接事实、目标分支差异和回灌参考。

脚本只封装安全动作。高风险 Git 操作只给方案，不脚本化执行。