# 编排 Skill 跳过 Git Skill 直接用原生命令

## 发生了什么

在 work-orchestrator 的 Execute 阶段需要创建 Git 分支时，AI 直接用了 `git switch -c` 而不是路由到 `git-trunk-workflow` 的脚本。git-trunk-workflow 明明可用且匹配任务，但 AI 跳过了路由步骤。

## 根因

1. work-orchestrator 的能力路由是建议性的（"匹配 description，判断是否合适"），不是强制性的。
2. AI 的注意力在实现任务本身，而非"我应该通过哪个 skill 来做"。
3. 没有机制区分"用 skill 做"和"自己做"——两条路径同样可用。

## 影响

- Git 操作绕过了 git-trunk-workflow 的安全围栏（保护分支检查、审计日志、暂存校验）
- 分支创建成功了，但绕过了设计的安全层

## 经验

1. **"动态匹配"没有强制力就只是建议。** 路由依赖 AI 判断时，认知负载高的场景下会被跳过。
2. **修复方向不是"匹配得更好"，而是"有 skill 时禁止绕过"。** 如果 skill 可用，原生命令路径应该被显式禁止。
3. **规则结构应该是：有 skill → 必须用；没 skill → 自由发挥。** 这是清晰的、二元的，不依赖判断质量。

## 围栏化

**已完成：**
- work-orchestrator SKILL.md 重写：加入"不可绕过清单"——有匹配 skill 时，原生命令被显式禁止
- 规则变为二元判断：skill 可用 → 必须用 skill。skill 不可用 → 需用户确认后自由发挥。

**结构性限制：**
- 这仍然是提示词级规则。真正的围栏在下游——git-trunk-workflow 的脚本本身就是代码围栏。编排层的职责是路由到那些脚本，而路由本身在当前架构下无法代码化。
- 纵深防御：即使编排路由失败，git-trunk-workflow 的脚本本身仍能防止最坏结果（不 force push、不推保护分支）——前提是被使用了。
