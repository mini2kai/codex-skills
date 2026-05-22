# Codex Skills

这是一个 Codex skills 集合仓库。仓库里的每个 `skills/<skill-name>/` 子目录都是一个完整、可独立安装的 skill。

当前仓库地址：

```text
https://github.com/mini2kai/codex-skills
```

## 快速使用

### 安装指定 Skill

在你希望放置 skill 的目录下执行：

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill lark-cli-config
```

安装 `postgres-query`：

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill postgres-query
```

安装 `codex-skill-dev`：

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill codex-skill-dev
```

安装 `server-docker-logs-readonly`：

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill server-docker-logs-readonly
```

安装结果：

```text
<当前执行目录>\<skill-name>
```

例如当前目录是 `C:\Users\you\.codex\skills`，安装 `codex-skill-dev` 后结果就是：

```text
C:\Users\you\.codex\skills\codex-skill-dev
```

### 查询可安装 Skill

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill -List
```

当前包含：

| Skill | 说明 |
| --- | --- |
| `lark-cli-config` | 分步引导 lark-cli 授权配置，封装 Feishu document/wiki/sheet 安全操作。 |
| `postgres-query` | 引导式 PostgreSQL 临时连接配置、只读查询、表结构查看和查询计划分析；风险操作只生成 SQL 不执行。 |
| `codex-skill-dev` | 中文 Codex skill 开发、验证、仓库同步和 GitHub 发布流程；沉淀 Windows/PowerShell、编码、校验和常见错误避坑。 |
| `server-docker-logs-readonly` | 本地脚本白名单模式查询 Docker 容器内指定日志目录下的文件；配置文件随 skill 一起下载。 |

## 常用命令

### 安装 `lark-cli-config`

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill lark-cli-config
```

### 安装 `postgres-query`

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill postgres-query
```

`postgres-query` 默认只执行只读查询。首次实际连接 PostgreSQL 时，如果本机缺少 Python 驱动，skill 会用中文引导安装 `psycopg` 或 `psycopg2`，并在安装前等待确认。

### 安装 `codex-skill-dev`

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill codex-skill-dev
```

### 安装 `server-docker-logs-readonly`

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill server-docker-logs-readonly
```

`server-docker-logs-readonly` 用于通过本地白名单脚本查询 Docker 容器内指定日志目录下的服务日志文件。通用脚本和配置文件 `skills/server-docker-logs-readonly/scripts/targets.local.json` 会随 skill 一起下载；公开仓库里只有示例数据，安装后在自己的 skill 目录中填写目标、SSH 信息、容器和 `logDir`。日志文件名不固定，先列出目录文件，再指定 `File` 查询。不要把填过真实信息的配置提交回 GitHub。Codex 不允许直接运行 SSH、Docker、docker exec、sudo 或任何服务器命令。

`codex-skill-dev` 用于开发、验证、同步和发布本仓库里的 skill，包含 Windows/PowerShell、UTF-8 编码、manifest/README 同步和 GitHub 发布避坑流程。

### 覆盖安装

默认不会覆盖同名目录。确认要覆盖时使用 `-Force`：

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill codex-skill-dev -Force
```

覆盖前会自动备份旧版本到当前目录下的 `.backup`：

```text
<当前执行目录>\.backup\<skill-name>-yyyyMMdd-HHmmss
```

### 查询列表

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill -List
```

### 指定分支或 Tag

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill codex-skill-dev -Ref v1.0.0
```

### 指定仓库

默认仓库是 `mini2kai/codex-skills`。如果 fork 了仓库，可以这样指定：

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill codex-skill-dev -Repo owner/repo -Ref main
```

### 下载脚本后执行

如果不想直接 `irm | iex`，可以先下载脚本再执行：

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 -OutFile install.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1 codex-skill-dev
```

查询列表：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -List
```

覆盖安装：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 codex-skill-dev -Force
```

## 参数说明

| 参数 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `Skill` | 字符串 | 无 | 要安装的 skill 名称，例如 `lark-cli-config`、`postgres-query` 或 `codex-skill-dev`。使用 `-List` 时可以不传。 |
| `-List` | 开关 | 关闭 | 查询仓库里当前可安装的 skill。 |
| `-Force` | 开关 | 关闭 | 允许覆盖当前目录下已有的同名 skill。覆盖前会自动备份。 |
| `-Repo` | 字符串 | `mini2kai/codex-skills` | GitHub 仓库，格式是 `owner/repo`。 |
| `-Ref` | 字符串 | `main` | Git 分支名、tag 或 ref，例如 `main`、`v1.0.0`。 |

## 交互和错误提示

安装器所有面向使用者的提示都使用中文。

常见情况：

### 同名 Skill 已存在

不会覆盖，会提示：

```text
skill 已存在，未覆盖：<当前执行目录>\codex-skill-dev
覆盖安装：irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill codex-skill-dev -Force
换目录安装：cd <目标目录> 后重新执行安装命令。
```

### Skill 名称不存在

会提示查询列表命令：

```powershell
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill -List
```

### 网络或仓库地址错误

会提示检查网络、仓库地址、分支或 tag，并给出查询和安装示例命令。

## 安装位置

本安装器默认安装到当前执行目录：

```text
<当前执行目录>\<skill-name>
```

也就是说，使用者在哪个目录下运行安装命令，就会把 skill 复制到哪个目录下。

要安装到 Codex 官方 skills 目录，可以先进入该目录：

```powershell
cd $HOME\.codex\skills
irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex; Install-CodexSkill codex-skill-dev
```

安装到官方目录后，重启 Codex 才会加载新 skill。

## Codex 官方 Skill Installer

也可以使用 Codex 自带的 skill-installer：

```powershell
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo mini2kai/codex-skills --path skills/lark-cli-config
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo mini2kai/codex-skills --path skills/postgres-query
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo mini2kai/codex-skills --path skills/codex-skill-dev
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo mini2kai/codex-skills --path skills/server-docker-logs-readonly
```

## 本地仓库安装

如果已经 clone 了这个仓库，可以从任何目录执行本地安装器。skill 仍然会安装到你执行命令时所在的当前目录：

```powershell
powershell -ExecutionPolicy Bypass -File C:\path\to\codex-skills\scripts\install.ps1 codex-skill-dev
```

如果你就在仓库根目录执行下面的命令，skill 会安装到仓库根目录下的 `codex-skill-dev`：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 codex-skill-dev
```

## 仓库结构

```text
codex-skills/
├── skills/
│   ├── lark-cli-config/
│   │   ├── SKILL.md
│   │   ├── agents/
│   │   ├── references/
│   │   └── scripts/
│   ├── postgres-query/
│   │   ├── SKILL.md
│   │   ├── agents/
│   │   ├── references/
│   │   └── scripts/
│   ├── server-docker-logs-readonly/
│   │   ├── SKILL.md
│   │   ├── agents/
│   │   └── scripts/
│   └── codex-skill-dev/
│       ├── SKILL.md
│       ├── agents/
│       ├── references/
│       └── scripts/
├── scripts/
│   └── install.ps1
├── manifest.json
└── README.md
```

## 添加新 Skill

每个 skill 目录应该是完整结构：

```text
skills/<skill-name>/
├── SKILL.md
├── agents/
├── references/
└── scripts/
```

建议目录名、安装名和 `SKILL.md` frontmatter 里的 `name` 保持一致。

新增 skill 后同步更新 `manifest.json`，这样 `Install-CodexSkill -List` 能展示中文说明。开发新 skill 时可先使用 `codex-skill-dev` 进行预检、同步和发布。
