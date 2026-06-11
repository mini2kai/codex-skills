# git-trunk-workflow：保护分支靠代码，不靠信任

## 问题

AI Agent 执行 Git 操作很有用但很危险。一次 `git push --force` 或误合并到 main 就能毁掉工作。提示词写"不要 force push"是不可靠的——本仓库自己的事故记录已经证明了这一点。

## 设计理念

**保护分支、安全暂存和 push 限制由脚本逻辑强制执行。无论 AI 被要求做什么，它都无法绕过这些限制。**

AI 可以自由决定提交什么内容、怎么描述，但脚本物理上阻止它 push 到保护分支、force push 或盲目暂存所有文件。

## 实现思路

### 1. 保护分支注册表

`git_common.ps1` 中的 `Test-ProtectedBranch` 维护硬编码列表：
- 命名：main、master、dev、uat、prod、production、staging
- 前缀：release/*、hotfix/*

任何可能修改这些分支的脚本都会先检查该函数，匹配则直接退出。

### 2. Push 限制

`push_ai_branch.ps1` 在 push 前执行两个检查：
1. 当前分支必须以 `ai/` 开头
2. 当前分支不能是保护分支

只执行 `git push -u origin <当前ai分支>`。没有 `--force`，没有替代远端引用。

### 3. 暂存路径校验

`stage_paths.ps1` 拒绝：
- `.`、`*`、`:/`、`--all`、`-A`、`-u`（全量暂存）
- 包含通配符的路径
- 空路径

只接受显式文件路径。防止"git add 所有文件"导致无关或敏感文件被提交。

### 4. 分支命名强制

`Test-AiBranchName` 要求格式：`ai/<source>/<YYYYMMDD>-<type>-<topic>`

确保每个 AI 分支都能追溯到来源分支、日期和用途。

### 5. 安全同步

`create_ai_branch.ps1` 只通过 `git pull --ff-only` 同步。如果 fast-forward 失败（历史分叉），脚本停止。不自动 merge，不自动 rebase。

### 6. Git 状态守卫

`Assert-NoGitOperationInProgress` 检查 MERGE_HEAD、REBASE_HEAD、CHERRY_PICK_HEAD 和 rebase 目录。如果存在任何中间状态，拒绝所有操作直到用户解决。

## 什么被刻意删掉了

- **10 步流程文档**：模型知道 Git 流程
- **提交信息模板**：模型自然能写中文
- **合并/回灌策略指南**：模型能根据上下文评估
- **验证清单格式**：模型自己决定验证什么
- **分支生命周期管理细节**：模型能给清理建议
- **平台配置**（openai.yaml）：已废弃

## 文件结构

```
git-trunk-workflow/
├── SKILL.md                     # 围栏规则 + 脚本入口（~45 行）
├── DESIGN.md                    # 英文设计文档
├── DESIGN_cn.md                 # 本文件
└── scripts/
    ├── git_common.ps1           # 所有围栏逻辑（保护分支、校验）
    ├── git_preflight.ps1        # 只读仓库状态检查
    ├── create_ai_branch.ps1     # 安全分支创建 + ff-only 同步
    ├── stage_paths.ps1          # 只允许显式路径暂存
    ├── commit_cn.ps1            # 中文提交 helper
    ├── push_ai_branch.ps1       # 只 push ai/*，不 force
    ├── git_handoff_summary.ps1  # 交接事实采集
    └── test_git_safety.py       # 安全测试
```
