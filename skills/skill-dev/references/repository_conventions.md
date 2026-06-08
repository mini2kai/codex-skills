# 仓库约定

本文件用于在 `mini2kai/m2k-skills` 仓库中开发或更新 skill 时确认项目级约定。

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

- `manifest.json`：安装器列表、仓库索引和 skill 独立版本号。
- `README.md`：安装命令、可安装列表、仓库结构。
- `scripts/install.ps1`：必要时更新示例提示。

## Skill 版本

每个 `manifest.json` 的 skill 条目都必须包含 `version`，格式为 `x.y.z`。

- 新增 skill 从 `0.1.0` 开始。
- 文档、提示词、校验规则的小修订递增 patch，例如 `0.1.0` -> `0.1.1`。
- 新增兼容能力、脚本参数或安装器可识别的新元数据递增 minor，例如 `0.1.1` -> `0.2.0`。
- 改名、移除能力、改变默认行为或破坏兼容的修改递增 major，例如 `0.2.0` -> `1.0.0`。
- 安装器的“本地/线上”对比基于 skill `version`；commit 仅作为安装来源追踪信息保留。

## 安装器约定

安装器默认从 `manifest.json` 读取可安装 skill。新增 skill 后，`Install-CodexSkill -List` 应展示中文说明。

常用安装命令：

```powershell
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill <skill-name>
```

覆盖安装：

```powershell
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill <skill-name> -Force
```

## README 同步内容

新增或更新 skill 时至少同步：

- 快速安装命令。
- “当前包含”表格。
- 常用命令中的安装示例。
- 参数说明中的示例 skill 名称。
- Codex 官方 skill-installer 示例。
- 仓库结构树。
- 版本号说明或相关示例。

## GitHub 约定

默认推送到：

```text
origin main
```

提交信息必须使用中文，简要写清楚修改内容，例如：

```text
新增 codex skill 开发流程
更新 postgres query 使用指引
```
