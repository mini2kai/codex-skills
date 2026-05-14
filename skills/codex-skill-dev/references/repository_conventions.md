# 仓库约定

本文件用于在 `mini2kai/codex-skills` 仓库中开发或更新 skill 时确认项目级约定。

## 目录结构

每个 skill 放在：

```text
skills/<skill-name>/
├── SKILL.md
├── agents/
│   └── openai.yaml
├── references/
└── scripts/
```

`assets/` 只在确实需要模板、图片、字体或其他输出资源时创建。

## 仓库文件

新增或改名 skill 后同步：

- `manifest.json`：安装器列表和仓库索引。
- `README.md`：安装命令、可安装列表、仓库结构。
- `scripts/install.ps1`：必要时更新示例提示。

## 安装器约定

安装器默认从 `manifest.json` 读取可安装 skill。新增 skill 后，`Install-CodexSkill -List` 应展示中文说明。

常用安装命令：

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill <skill-name>
```

覆盖安装：

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill <skill-name> -Force
```

## README 同步内容

新增 skill 时至少同步：

- 快速安装命令。
- “当前包含”表格。
- 常用命令中的安装示例。
- 参数说明中的示例 skill 名称。
- Codex 官方 skill-installer 示例。
- 仓库结构树。

## GitHub 约定

默认推送到：

```text
origin main
```

提交信息使用英文动词短句，例如：

```text
Add codex skill development workflow
Update postgres query skill guidance
```
