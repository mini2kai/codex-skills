# server-docker-logs-readonly：白名单脚本作为唯一入口

## 问题

AI Agent 需要读取服务器日志来排查问题，但给它 SSH 权限是不可接受的——一条错误命令就可能修改服务器状态、泄露凭据或导致服务中断。

传统做法是在提示词里写"不要执行危险命令"。但提示词约束可以被忽略。你需要一个保证：AI 物理上不可能执行只读日志检索以外的任何操作。

## 设计理念

**不给 SSH shell 权限。只给白名单脚本。每个参数都校验。每个操作都审计。**

AI 永远不直接接触服务器。它只能调用一组固定的 PowerShell 脚本，每个脚本：
1. 用严格的模式校验所有输入
2. 从校验通过的组件构造只读远程命令
3. 在执行前对构造的命令做白名单匹配 + 危险片段黑名单扫描
4. 通过受控的 SSH helper 执行
5. 将操作记录到审计日志

## 实现思路

### 1. 白名单脚本模型

AI 只能执行 9 个特定的 `.ps1` 脚本。每个脚本：
- 接收命名参数（`-Target`、`-Source`、`-File`、`-Keyword`）
- 用 `Assert-Safe*` 函数校验每个参数
- 从安全构建块组装远程命令
- 执行前通过 `Assert-RemoteReadCommand` 检查

没有通用的"在服务器上执行这条命令"的路径。

### 2. 远程命令围栏（Assert-RemoteReadCommand）

每条构造的远程命令必须通过三重检查：

1. **单行限制** — 含换行符即拒绝（防止通过换行注入）
2. **白名单模式匹配** — 必须以 `cd -- /safe/path &&` 或 `docker exec container /bin/sh -lc` 或 `docker ps/inspect` 开头
3. **路径穿越拒绝** — 命令中出现 `..` 即拒绝
4. **危险片段扫描** — 30+ 个危险子串（rm、mv、chmod、curl、wget、kill、systemctl 等）大小写不敏感拒绝

### 3. 输入校验层

- `Assert-SafeName`：目标/账号/日志源/容器名只允许 `[A-Za-z0-9_.-]`
- `Assert-SafeAbsDir`：必须绝对路径，不能有 `..`、`\\`、`//`
- `Assert-SafeRelDir`：必须相对路径，不能有 `..`、不能以 `/` 开头
- `Assert-SafeLogFile`：只允许简单文件名，不能有路径分隔符
- `Assert-Tail`：硬上限 5000
- `Assert-MaxMatches`：硬上限 1000
- Keyword：最长 200 字符，不允许 shell 元字符

### 4. 权限模型

每个 SSH 账号有显式权限：
- `permissions.hostDir`：可读取主机目录日志
- `permissions.docker`：可读取 Docker 容器日志

`docker` 类型日志源需要 `docker` 权限。`host_dir` 类型需要 `hostDir` 权限。缺少权限 = 立即拒绝。

### 5. 审计留痕

每次远程读取操作记录到 `logs/server-access-YYYY-MM-DD.jsonl`：
- 时间戳、账号、主机（输出中脱敏）、命令类型、完整远程命令
- 7 天自动轮转

### 6. 凭据保护

- `targets.local.json` 不进 Git
- 输出不包含真实 host、SSH 用户、密钥路径或密码
- AI 只看到 target/account/source 别名

## 什么被刻意删掉了

- **分步流程说明**：模型知道先列目标再读文件
- **命令模板**：模型能从脚本参数推断
- **参数文档**：脚本已通过 Assert-* 强制校验
- **错误码参考**：脚本 JSON 输出已自描述
- **平台配置**（openai.yaml）：已废弃

## 测试发现并修复的漏洞

测试套件（`test_command_safety.py`）暴露并验证了以下修复：
- Docker exec 命令中引号后紧跟危险关键词（`'rm`、`'curl`）未被拦截
- 白名单匹配的路径中可包含 `..` 实现路径穿越

## 文件结构

```
server-docker-logs-readonly/
├── SKILL.md                    # 围栏规则 + 脚本入口（~45 行）
├── DESIGN.md                   # 英文设计文档
├── DESIGN_cn.md                # 本文件
└── scripts/
    ├── common.ps1              # 所有围栏逻辑（白名单、黑名单、校验、审计）
    ├── ssh_run.py              # SSH 执行 helper（受 common.ps1 控制）
    ├── list-targets.ps1        # 白名单入口脚本
    ├── list-accounts.ps1
    ├── list-sources.ps1
    ├── list-log-files.ps1
    ├── get-log-file.ps1
    ├── search-logs.ps1
    ├── recent-errors.ps1
    ├── list-containers.ps1
    ├── get-container-info.ps1
    ├── test_command_safety.py  # 安全测试
    └── targets.local.json      # 本地配置（不进 Git）
```
