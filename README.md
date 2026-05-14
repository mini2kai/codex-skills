# Codex Skills

这是一个 Codex skills 集合仓库。仓库里的每个 `skills/<skill-name>/` 子目录都是一个完整、可独立安装的 skill。

当前已包含：

- `lark-cli-config`：用于 Feishu/Lark 文档、wiki、sheet、drive 和 `lark-cli` 操作前的环境检查、授权引导、scope 修复和高风险操作确认。

## 快速安装

### GitHub Raw 一行安装

在你希望放置 skill 的目录下执行：

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install-lark-cli-config.ps1 | iex
```

例如你在 `C:\Users\you\Desktop\skills` 目录执行，安装结果就是：

```text
C:\Users\you\Desktop\skills\lark-cli-config
```

这个快捷脚本内部会先加载通用安装器 `scripts/install.ps1`，再自动执行：

```powershell
Install-CodexSkill lark-cli-config
```

所以使用者不需要再手动输入 skill 名。

### Windows PowerShell 两步方式

也可以先下载通用安装器，再安装指定 skill：

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 -OutFile install.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1 lark-cli-config
```

这个方式同样会安装到执行命令时所在的当前目录。

### 通用安装器一行方式

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill lark-cli-config
```

### Codex 官方 skill-installer 方式

如果你要安装到 Codex 官方 skills 目录，可以使用 Codex 自带的 skill-installer：

```powershell
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo mini2kai/codex-skills --path skills/lark-cli-config
```

安装到官方目录后，需要重启 Codex。

## 安装位置

本仓库的 `install.ps1` 默认安装到当前执行目录：

```text
<当前执行目录>\<skill-name>
```

也就是说，使用者在哪个目录下运行安装命令，就会把 skill 复制到哪个目录下。

如果目标目录已经存在同名 skill，默认会显示中文提示并停止，不会覆盖。确认要替换时使用 `-Force`：

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill lark-cli-config -Force
```

覆盖前会自动备份旧版本到当前目录下的 `.backup`：

```text
<当前执行目录>\.backup\<skill-name>-yyyyMMdd-HHmmss
```

## 常用命令

列出仓库里的 skill：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -List
```

指定分支或 tag 安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 lark-cli-config -Ref v1.0.0
```

## 本地仓库安装

如果已经 clone 了这个仓库，也可以从任何目录执行本地安装器。skill 仍然会安装到你执行命令时所在的当前目录：

```powershell
powershell -ExecutionPolicy Bypass -File C:\path\to\codex-skills\scripts\install.ps1 lark-cli-config
```

如果你就在仓库根目录执行下面的命令，skill 会安装到仓库根目录下的 `lark-cli-config`：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 lark-cli-config
```

## 仓库结构

```text
codex-skills/
├── skills/
│   └── lark-cli-config/
│       ├── SKILL.md
│       ├── agents/
│       ├── references/
│       └── scripts/
├── scripts/
│   ├── install.ps1
│   └── install-lark-cli-config.ps1
├── manifest.json
└── README.md
```

## install.ps1 的行为

`scripts/install.ps1` 的设计规则：

- 支持 `Skill`、`Repo`、`Ref`、`Force`、`List` 参数。
- 使用当前执行目录作为安装根目录。
- 从本地仓库执行时，优先复制本地 `skills/<skill-name>`。
- 单独下载脚本或远程执行脚本时，会下载 GitHub 仓库 zip，再复制 `skills/<skill-name>`。
- 默认不覆盖已有 skill。
- 使用 `-Force` 时，会先备份旧 skill，再复制新 skill。
- 安装前校验目标路径必须位于当前执行目录下。
- 只复制文件，不执行 skill 内部脚本。

## 添加新 skill

每个 skill 目录应该是完整结构：

```text
skills/<skill-name>/
├── SKILL.md
├── agents/
├── references/
└── scripts/
```

建议目录名、安装名和 `SKILL.md` frontmatter 里的 `name` 保持一致。
