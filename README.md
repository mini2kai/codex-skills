# M2K Skills

[![GitHub stars](https://img.shields.io/github/stars/mini2kai/m2k-skills?style=social)](https://github.com/mini2kai/m2k-skills/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/mini2kai/m2k-skills?style=social)](https://github.com/mini2kai/m2k-skills/forks)
[![GitHub issues](https://img.shields.io/github/issues/mini2kai/m2k-skills)](https://github.com/mini2kai/m2k-skills/issues)
[![Skills](https://img.shields.io/badge/skills-7-success)](#skill-catalog)
[![Manager](https://img.shields.io/badge/manager-m2k--skills--tools-00A6D6)](#m2k-skills-tools)
[![Installer](https://img.shields.io/badge/installer-PowerShell-5391FE)](#installation)
[![License](https://img.shields.io/badge/license-Non--Commercial-lightgrey)](#license)
[![Agent](https://img.shields.io/badge/agent-skills-black)](#using-with-agent-tools)

一组可复用、可审计、可安全安装的 M2K Skills，用于把高频 AI 协作流程沉淀为稳定能力。

本仓库面向日常研发、数据查询、飞书/Lark 协作、服务器日志只读排查、AI 工作日报统计，以及 Skill 本身的开发发布流程。每个 `skills/<skill-name>/` 目录都是一个完整、可独立安装的 skill，可以按需安装到 Codex、Claude 或其他支持本地 skill/指令目录的 agent 工具中，也可以在团队内部 fork 后维护自己的版本。

## Highlights

- **独立安装**：每个 skill 可以单独安装、升级和覆盖，不需要 clone 整个仓库。
- **安全默认**：数据库默认只读、服务器日志走白名单脚本、AI 工作日报先预览再生成。
- **本地优先**：用户配置、Excel、日志、preview、state 等本地文件不提交 Git。
- **可审计**：安装覆盖会自动备份旧目录，版本对比使用每个 skill 独立的语义版本号，commit 仅保留为来源追踪信息。
- **适合中文工作流**：面向用户的流程说明、错误提示和交互话术以中文为主。
- **Windows 友好**：安装器和示例命令优先覆盖 PowerShell 使用场景。

## Installation

### m2k-skills-tools

推荐使用漂亮的终端管理器安装和更新本仓库的 skills。发布到 PyPI 后可直接运行：

```powershell
uvx --from m2k-skills-tools m2k-skills-tools
```

无参数启动会进入全屏 TUI，并先选择安装目标目录。顶部 Logo 常驻，左侧菜单切换页面，右侧显示当前页面内容。`←` / `→` 切换左右区域，`↑` / `↓` 移动选中项，`Space` 用 `□` / `✓` 勾选，`Enter` 确认，`/` 聚焦筛选框，`b` 返回首页，`r` 刷新，`q` 退出。Tab 已禁用，统一使用方向键。选择目标目录后会后台预加载安装状态和环境检查；manifest/status/doctor 在当前 TUI 会话内缓存，按 `r` 强制刷新。安装/更新合并为一个页面，第一项支持全选/取消全选，每个 skill 下方显示简介和依赖，状态固定显示在右侧；安装/更新、详情、配置列表支持按名称、状态、描述、标签和依赖筛选；未安装项选中后安装，非最新项选中后更新，最新项不可选。安装/更新过程会显示下载、解压、复制文件、恢复配置等进度和日志。

常用命令：

```powershell
# 查看 Codex skills 目录中的安装状态
uvx --from m2k-skills-tools m2k-skills-tools status --target codex

# 安装到 Codex skills 目录
uvx --from m2k-skills-tools m2k-skills-tools add ai-worklog --target codex

# 安装到 Claude skills 目录
uvx --from m2k-skills-tools m2k-skills-tools add ai-worklog --target claude

# 更新全部已安装 skill，会二次确认并自动备份旧目录
uvx --from m2k-skills-tools m2k-skills-tools update all --target codex
```

工具会展示本机安装状态、安装时间、本地版本、线上版本，并支持打开已安装 skill 的本地配置文件。

本仓库开发调试时可以直接运行源码包：

```powershell
uv run --project packages/m2k-skills-tools m2k-skills-tools status --target codex
```

如果只是本地长期试用，可以安装为 uv tool，后续直接运行命令：

```powershell
uv tool install -e packages/m2k-skills-tools
m2k-skills-tools --target codex
```

### Legacy PowerShell Installer

推荐安装到 Codex 官方 skills 目录：

```powershell
cd $HOME\.codex\skills
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill ai-worklog
```

安装完成后，重启 Codex 让新 skill 生效。

查询当前可安装的 skill：

```powershell
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill -List
```

安装其他 skill 时，将 `ai-worklog` 替换为下面目录中的任意 skill 名称即可。

## Skill Catalog

| Skill | 适用场景 | 主要依赖 |
| --- | --- | --- |
| `ai-worklog` | 汇总 Codex、Claude Code/CLI、Git 等 AI 协作痕迹，生成日报、报工摘要和耗时 Excel。 | Python；Git 可选；Excel 输出需要 `openpyxl` |
| `skill-dev` | 开发、校验、版本管理、同步和发布本仓库的 Codex skill，沉淀 Windows/PowerShell、编码和 GitHub 发布规范。 | Python, Git |
| `lark-cli-config` | 引导 Feishu/Lark CLI 授权配置，安全读取和维护文档、Wiki、表格、Drive 等资源。 | Python, Node.js, `npx`, `@larksuite/cli` |
| `postgres-query` | PostgreSQL 临时连接、本机多 profile 管理、只读查询、表结构查看和查询计划分析。 | Python, `psycopg` 或 `psycopg2` |
| `server-docker-logs-readonly` | 通过本地白名单脚本只读查询服务器日志，Docker 容器日志作为受控备用路径。 | PowerShell, Python, `paramiko` |
| `web-demo-publisher` | 对话式生成、预览和发布 Web Demo、Slidev、Vite/静态站点到 `localhost:9999`，可选检测 cpolar 外网地址。 | PowerShell；Node.js 可选；cpolar 可选 |
| `work-orchestrator` | 手动触发的轻量总控 Skill，用于先分析不修改、证据收集、影响评估和多 skill 编排。 | 无 |

## Quick Commands

```powershell
# AI 工作日报 / 报工统计
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill ai-worklog

# Skill 开发、版本管理和发布流程
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill skill-dev

# 飞书 / Lark CLI 配置和文档流程
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill lark-cli-config

# PostgreSQL 只读查询
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill postgres-query

# 服务器日志只读排查
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill server-docker-logs-readonly

# Web Demo 生成、预览和发布
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill web-demo-publisher

# 手动总控编排
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill work-orchestrator
```

## Installer Behavior

安装器会把指定 skill 复制到当前执行目录：

```text
<current-directory>\<skill-name>
```

例如在 `C:\Users\you\.codex\skills` 下执行安装 `ai-worklog`，结果是：

```text
C:\Users\you\.codex\skills\ai-worklog
```

默认不会覆盖同名目录。需要覆盖安装时使用 `-Force`：

```powershell
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill ai-worklog -Force
```

覆盖前会自动备份旧目录：

```text
<current-directory>\.backup\<skill-name>-yyyyMMdd-HHmmss
```

覆盖安装时的本地文件策略：

- 旧 skill 目录会完整备份，便于回滚和审计。
- `*.local.json`、`*.local.jsonc` 会在新版配置结构兼容时自动恢复。
- 如果新版配置结构发生变化，安装器会保留新版模板，并提示用户从备份中手动迁移。
- Excel、日志、preview、state 等运行生成文件只保留在备份目录，不自动恢复到新版 skill。

## Installer Options

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `Skill` | 无 | 要安装的 skill 名称，例如 `ai-worklog`、`postgres-query`。使用 `-List` 时可以不传。 |
| `-List` | 关闭 | 查询仓库里当前可安装的 skill。 |
| `-Force` | 关闭 | 允许覆盖当前目录下已有的同名 skill，覆盖前会完整备份旧目录。 |
| `-Repo` | `mini2kai/m2k-skills` | GitHub 仓库，格式为 `owner/repo`，适合 fork 后安装。 |
| `-Ref` | `main` | Git 分支、tag 或 ref，例如 `main`、`v1.0.0`。 |

从指定 tag 或分支安装：

```powershell
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill ai-worklog -Ref v1.0.0
```

从 fork 安装：

```powershell
irm https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 | iex; Install-CodexSkill ai-worklog -Repo owner/repo -Ref main
```

如果不想直接执行 `irm | iex`，可以先下载安装器：

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/mini2kai/m2k-skills/main/scripts/install.ps1 -OutFile install.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1 ai-worklog
```

## Using With Agent Tools

Codex 用户也可以通过 Codex 自带的 `skill-installer` 从 GitHub 安装：

```powershell
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo mini2kai/m2k-skills --path skills/ai-worklog
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo mini2kai/m2k-skills --path skills/skill-dev
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo mini2kai/m2k-skills --path skills/lark-cli-config
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo mini2kai/m2k-skills --path skills/postgres-query
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo mini2kai/m2k-skills --path skills/server-docker-logs-readonly
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo mini2kai/m2k-skills --path skills/web-demo-publisher
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo mini2kai/m2k-skills --path skills/work-orchestrator
```

## Usage Notes

### `ai-worklog`

用于统计某一天 AI 协作完成的工作内容、耗时、证据和报工摘要。

推荐通过自然语言触发：

```text
[$ai-worklog] 帮我整理今天 AI 完成的内容
```

默认流程是“先生成预览，再确认生成正式 Excel”。当你明确要求“全部纳入”时，可以把预览中的候选记录全部纳入后直接生成正式台账。

常用脚本入口：

```powershell
python .\ai-worklog\scripts\ai_worklog_collect.py --date today --preview
python .\ai-worklog\scripts\ai_worklog_collect.py --date today --from-preview .\ai-worklog\data\ai_worklog_preview.xlsx --excel --format markdown
```

### `postgres-query`

默认只执行只读查询。首次连接 PostgreSQL 时，如果本机缺少 Python 驱动，skill 会引导安装 `psycopg` 或 `psycopg2`。

本地连接配置文件：

```text
postgres-query\scripts\connections.local.json
```

建议用 `passwordEnv` 指向环境变量保存密码，不要在配置文件里保存明文密码。

```powershell
python .\postgres-query\scripts\pg_profiles.py
python .\postgres-query\scripts\pg_query.py --profile dev --sql "select now()" --limit 20
```

### `server-docker-logs-readonly`

该 skill 只允许通过本地白名单脚本查询服务器日志。目标配置文件：

```text
server-docker-logs-readonly\scripts\targets.local.json
```

使用该流程时，Codex 不应直接运行 SSH、Docker、`docker exec`、`sudo` 或任意服务器命令。

### `skill-dev`

用于维护本仓库，包括 skill 开发、格式校验、独立版本号维护、manifest 同步、README 更新、Windows/PowerShell 避坑和 GitHub 发布流程。

### `web-demo-publisher`

用于把网页、Slidev、Vite 应用或静态页面发布到固定本地端口 `localhost:9999`，并在本机 cpolar 可用时提取公网访问地址。

```powershell
powershell -ExecutionPolicy Bypass -File .\web-demo-publisher\scripts\publish.ps1 -ProjectPath . -UseCpolar auto
powershell -ExecutionPolicy Bypass -File .\web-demo-publisher\scripts\generate-from-template.ps1 -Template landing-product -DestinationPath .\demo-page
```

## Repository Layout

```text
m2k-skills/
|-- skills/
|   |-- ai-worklog/
|   |   |-- SKILL.md
|   |   |-- agents/
|   |   |-- references/
|   |   `-- scripts/
|   |-- skill-dev/
|   |-- lark-cli-config/
|   |-- postgres-query/
|   |-- server-docker-logs-readonly/
|   |-- web-demo-publisher/
|   `-- work-orchestrator/
|-- scripts/
|   `-- install.ps1
|-- packages/
|   `-- m2k-skills-tools/
|-- manifest.json
`-- README.md
```

## Development

新增或更新 skill 时，建议遵循以下流程：

1. 在 `skills/<skill-name>/` 下维护 `SKILL.md`、`agents/`、`references/`、`scripts/`。
2. 保持目录名、安装名和 `SKILL.md` frontmatter 中的 `name` 一致。
3. 只在确有需要时添加脚本、引用资料或 agent 配置。
4. 更新 `manifest.json`，确保每个 skill 条目包含 `version`，新 skill 从 `0.1.0` 开始，修改后按影响范围递增版本。
5. 更新 README 中的安装和使用说明。
6. 发布前运行仓库校验。

常用校验命令：

```powershell
python .\skills\skill-dev\scripts\skill_preflight.py --repo-root . --skill ai-worklog
python .\skills\skill-dev\scripts\validate_skill_repo.py --repo-root . --skill ai-worklog
python -m json.tool manifest.json
```

## Privacy And Safety

- 不提交密钥、token、cookie、数据库连接串、导出数据、Excel 台账、preview、state 或本地日志。
- 用户本地配置放在 `*.local.json` 或 `*.local.jsonc` 中。
- 数据库操作默认只读；风险写入或 DDL 请求只生成 SQL，不直接执行。
- 服务器日志读取必须走本地白名单脚本，并保留审计日志。
- AI 工作日报默认先生成隐私预览，再基于确认结果生成正式报告。

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=mini2kai/m2k-skills&type=Date)](https://www.star-history.com/#mini2kai/m2k-skills&Date)

## License

本项目采用自定义非商业许可：允许个人学习、自用，以及组织内部非商业使用；禁止未经授权的商业使用、转售、付费分发、商业 SaaS/服务集成或作为商业产品的一部分再发布。

如需商业使用，请先联系仓库作者获得书面授权。完整条款见 [LICENSE](./LICENSE)。
