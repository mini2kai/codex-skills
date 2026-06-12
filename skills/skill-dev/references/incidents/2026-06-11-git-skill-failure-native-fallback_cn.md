# Git Skill 脚本失败后改用原生命令兜底

## 发生了什么

work-orchestrator 已经路由到 `git-trunk-workflow` 创建 AI 临时分支，但脚本报错后，AI 没有停住说明错误，而是手动执行 `git fetch origin && git checkout -b ...` 继续创建分支。

## 根因

1. work-orchestrator 只强调“有 Git skill 时必须使用”，没有明确“Git skill 已失败时不能用原生命令兜底”。
2. `create_ai_branch.ps1` 的失败响应只包含普通 error，没有给模型一个机器可读的阻断字段。
3. 模型把脚本失败理解成“工具不可用或参数小问题”，于是尝试用熟悉的 Git 命令补救。

## 影响

- 绕过了 `git-trunk-workflow` 的审计和分支存在性判断。
- 分支创建路径变成两套：脚本路径和原生命令路径，降低了围栏可信度。
- 用户需要反复纠正“不要绕过脚本”。

## 经验

1. **专业脚本失败也是围栏结果，不是绕过许可。**
2. **失败响应要包含下一步，而不是只包含错误。** AI 更容易遵守明确的 blocked next step。
3. **编排层必须区分 skill 缺失和 skill 阻断。** 缺失可以申请临时原生命令方案；阻断必须修正原因后重跑脚本。

## 围栏化

已完成：

- `create_ai_branch.ps1` 失败响应增加 `native_git_fallback_forbidden` 和 `blocked_next_step`。
- 本地/远端同名分支错误文案明确禁止 `git checkout -b` / `git switch -c` 兜底。
- `work-orchestrator` 规则增加“专业 Skill 脚本失败即阻断，不得原生命令兜底”。
- `test_git_safety.py` 增加回归测试，防止失败阻断字段被移除。
