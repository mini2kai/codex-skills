# Codex Skills

这是一个 Codex skills 集合仓库。仓库里的每个 `skills/<skill-name>/` 子目录都是一个完整、可独立安装的 skill。

当前已包含：

- `lark-cli-config`：用于 Feishu/Lark 文档、wiki、sheet、drive 和 `lark-cli` 操作前的环境检查、授权引导、scope 修复和高风险操作确认。

## 快速安装

### Windows PowerShell 推荐方式

可以在任意目录执行，不需要进入本仓库目录：

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 -OutFile install.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1 lark-cli-config
```

安装完成后，重启 Codex，让新 skill 生效。


### GitHub Raw 一行安装

如果只想给别人一个最短的 GitHub 安装入口，可以使用这个命令：

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install-lark-cli-config.ps1 | iex
```

这个快捷脚本内部会先加载通用安装器 `scripts/install.ps1`，再自动执行：

```powershell
Install-CodexSkill lark-cli-config
```

所以使用者不需要再手动输入 skill 名。
### 一行命令方式

这种方式更方便，但会直接执行远程脚本。团队内默认更推荐上面的两步安装方式。

```powershell
iwr https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 -UseB | iex; Install-CodexSkill lark-cli-config
```

### Codex 官方 skill-installer 方式

```powershell
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo mini2kai/codex-skills --path skills/lark-cli-config
```

## 安装位置

安装脚本会自动识别当前用户目录，并安装到：

```text
$HOME\.codex\skills\<skill-name>
```

脚本不依赖执行命令时所在的目录，也不会写死任何使用者的本机路径。

## 常用命令

列出仓库里的 skill：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -List
```

指定分支或 tag 安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 lark-cli-config -Ref v1.0.0
```

如果本地已经存在同名 skill，默认会停止，不会覆盖。确认要替换时使用 `-Force`：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 lark-cli-config -Force
```

覆盖前会自动备份旧版本到：

```text
$HOME\.codex\skills\.backup\<skill-name>-yyyyMMdd-HHmmss
```

## 本地仓库安装

如果已经 clone 了这个仓库，也可以从仓库根目录执行：

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
│   └── install.ps1
├── manifest.json
└── README.md
```

## install.ps1 的行为

`scripts/install.ps1` 的设计规则：

- 支持 `Skill`、`Repo`、`Ref`、`Force`、`List` 参数。
- 使用当前用户的 `$HOME` 动态计算安装目录。
- 从本地仓库执行时，优先复制本地 `skills/<skill-name>`。
- 单独下载脚本或远程执行脚本时，会下载 GitHub 仓库 zip，再复制 `skills/<skill-name>`。
- 默认不覆盖已有 skill。
- 使用 `-Force` 时，会先备份旧 skill，再复制新 skill。
- 安装前校验目标路径必须位于 `$HOME\.codex\skills` 下。
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

