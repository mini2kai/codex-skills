---
name: codex-skill-dev
description: 中文 Codex skill 开发、更新、验证和 GitHub 发布流程。Use when the user asks to create, update, standardize, validate, package, document, install, publish, or sync a skill in the m2k-skills repository; when manifest.json, README.md, install.ps1, agents/openai.yaml, references, scripts, UTF-8 encoding, Windows PowerShell pitfalls, validation, git commit, or GitHub push are involved.
---

# Codex Skill Dev

## 触发规则

遇到创建、更新、规范化、验证、安装说明、GitHub 同步、发布 Codex skill 的任务时，先使用这个 skill。

典型场景：
- 新增 `skills/<skill-name>/`。
- 修改已有 skill 的 `SKILL.md`、`agents/openai.yaml`、`references/`、`scripts/`。
- 要求“中文文档和交互”“按本仓库 skill 风格整理”。
- 同步 `manifest.json`、`README.md`、`scripts/install.ps1`。
- 运行 `quick_validate.py`、检查 UTF-8 BOM、清理 `__pycache__`、提交并推送 GitHub。
- 总结开发过程中踩坑并沉淀到 skill。

## 标准流程

1. 确认需求和边界。
   - 明确 skill 名称、触发词、典型用户请求、是否需要 scripts/references/assets。
   - 如果用户只要求规划，不落文件；如果用户说“开始开发”，直接实现。
2. 检查仓库状态。
   - 运行 `git status --short`。
   - 如果有无关改动，不覆盖、不回退；必要时说明并只改目标文件。
3. 初始化或定位 skill。
   - 新 skill 优先使用系统 `skill-creator` 的 `init_skill.py`。
   - 若初始化中断，检查半成品目录，补齐缺失的 `agents/`、`references/`、`scripts/`。
4. 编写中文 skill 内容。
   - `SKILL.md` 主体中文，frontmatter 的 `description` 可中英混合以增强触发。
   - 用户交互话术中文；命令、参数、JSON 字段名保持英文。
   - 脚本面向用户的 `message`、`next_action` 使用中文。
5. 同步仓库元数据。
   - 更新 `manifest.json`。
   - 更新 `README.md` 的安装命令、列表、结构示例。
   - 必要时更新 `scripts/install.ps1` 的示例提示。
6. 编码处理。
   - 写入 Markdown、YAML、JSON、Python、PowerShell 后统一转无 BOM UTF-8。
   - 防止 PowerShell 展开 `$skill-name`，写 `default_prompt` 时必须复查。
7. 运行验证。
   - `quick_validate.py <skill-dir>`。
   - `python -m json.tool manifest.json`。
   - Python 脚本跑 `py_compile`。
   - 跑关键脚本的错误路径测试。
8. 清理验证副产物。
   - 删除目标 skill 内的 `__pycache__`。
   - 删除前必须确认路径在目标 skill 目录下。
9. 审查变更。
   - 运行 `git diff --stat`。
   - 对关键文件运行 `git diff`。
10. 提交和推送。
   - `git add`、`git commit`、`git push origin main` 分开执行。
   - 提交信息必须使用中文，简要写清楚修改内容。
   - 遇到 `.git/index.lock` 权限或 push 网络问题时，按审批流程提权重试。
   - 完成后运行 `git status --short` 确认干净。

## 写作风格

保持以下中文文档风格：

- 标题和正文中文。
- 先写触发规则，再写执行入口，再写标准流程。
- 规则要可执行，不写空泛原则。
- references 按需读取，不把长篇细节塞进 `SKILL.md`。
- 不创建 `README.md`、`CHANGELOG.md`、`INSTALLATION_GUIDE.md` 等 skill 内额外文档。

## 规则导航

按需读取这些 reference：

- 仓库约定：`references/repository_conventions.md`
- skill 格式：`references/skill_format.md`
- Windows/PowerShell 避坑：`references/windows_powershell_pitfalls.md`
- 验证清单：`references/validation_checklist.md`
- GitHub 发布：`references/github_publish.md`
- 常见失败：`references/common_failures.md`

## 脚本入口

脚本都输出 JSON，便于 agent 决策：

以下脚本位于当前 `codex-skill-dev` skill 自身的 `scripts/` 目录；`--repo-root` 指正在开发或校验的目标仓库根目录。

- 预检单个 skill：`python scripts/skill_preflight.py --repo-root <repo-root> --skill <skill-name>`
- 同步 manifest：`python scripts/sync_manifest.py --repo-root <repo-root> --skill <skill-name> --description "..." --tags a,b --requires python`
- 仓库级校验：`python scripts/validate_skill_repo.py --repo-root <repo-root> --skill <skill-name>`

## 安全底线

- 不写入密钥、token、cookie、数据库凭据、生产连接信息。
- 不提交 `.env`、临时凭据、数据库导出、`__pycache__`。
- 不回退用户已有改动。
- 不用 `git reset --hard` 或 `git checkout --`，除非用户明确要求。
- 递归删除前必须校验目标路径在预期目录内。
- 依赖下载、GitHub push、需要网络的操作失败时，按审批流程重试，不绕过。

## 最终反馈

完成后只报告：
- 新增或修改的 skill。
- 同步过的仓库文件。
- 运行过的验证和结果。
- commit hash 和 push 结果。
- 剩余 blocker。
