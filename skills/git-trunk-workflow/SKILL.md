---
name: git-trunk-workflow
description: Safe Git operations with protected-branch enforcement, explicit staging, Chinese commits, and audit trail. Use when the user asks to create a short-lived branch, stage files, write Chinese commits, push non-protected branches, or produce merge handoff notes. Does not merge long-lived branches, deploy, force push, discard changes, or run destructive Git operations.
---

# Git Trunk Workflow

## 围栏（代码强制，不可绕过）

以下限制由 `git_common.ps1` 和入口脚本代码执行：

- **保护分支拦截**：`Test-ProtectedBranch` 拒绝对 main/master/dev/uat/prod/release/* 的 push、commit 和分支创建。
- **只 push 非保护分支**：`push_branch.ps1` 检查当前分支不是保护分支，否则直接拒绝。
- **禁止 force push**：脚本只执行 `git push -u`，不带 `--force`。
- **保护分支上禁止 commit**：`commit_cn.ps1` 提交前检查当前分支不是保护分支。
- **禁止全量暂存**：`stage_paths.ps1` 拒绝 `.`、`*`、`--all`、`-A`、`-u`、通配符。
- **暂存前校验文件存在性**：路径不在 git status 中则拒绝，防止空暂存。
- **Git 中间状态检测**：`Assert-NoGitOperationInProgress` 检测 rebase/merge/cherry-pick 中间状态，有则拒绝执行。
- **同步只允许 ff-only**：`create_branch.ps1` 只执行 `pull --ff-only`，失败即停止。
- **Git 输出按 exit code 判定**：`Invoke-GitCapture` 捕获 stdout/stderr，但只用 Git exit code 判断失败，避免 remote/progress 信息误报 error。
- **脚本失败即阻断**：入口脚本失败时禁止改用原生 `git checkout -b`、`git switch -c`、`git add`、`git commit` 或 `git push` 兜底；必须说明错误，修正原因后重跑脚本。
- **审计留痕**：所有 git 操作记录到 `logs/git-ops-YYYY-MM-DD.jsonl`，7 天轮转。

## 脚本入口

```text
scripts/git_preflight.ps1      [-Fetch]
scripts/create_branch.ps1      -SourceBranch <branch> -BranchName <name> [-SyncSource]
scripts/stage_paths.ps1        -Paths path1,path2
scripts/commit_cn.ps1          -Title "..." -Bullets "...","..."
scripts/push_branch.ps1        [-Remote origin]
scripts/git_handoff_summary.ps1 -PrimaryTarget <branch> [-BackportTarget <branch>]
```

调用方式：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/<name>.ps1 [参数]`

## 围栏以内（AI 自由发挥）

在上述围栏保护下，AI 自行决定：

- 来源分支选择建议
- 分支命名（命名约定由调用方决定，例如 work-orchestrator 使用 `ai/<source>/<date>-<type>-<topic>` 格式）
- commit message 内容和详细程度
- 文件归属判断（本次任务 vs 无关变更）
- 验证方式和结果总结
- 交接摘要内容和格式
- 合并/回灌建议
