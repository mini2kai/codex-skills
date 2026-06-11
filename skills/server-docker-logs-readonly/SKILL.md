---
name: server-docker-logs-readonly
description: "本地脚本白名单模式的服务器日志只读查询。用于按配置读取服务器绝对目录日志，并保留 Docker 容器内日志作为备用方案。配置文件位于 skill 自身 scripts/targets.local.json；只能执行 skill 内置脚本，不能直接运行 ssh、docker、docker exec、sudo 或任何服务器命令。"
---

# Server Docker Logs Readonly

## 围栏（代码强制，不可绕过）

以下限制由 `common.ps1` 代码执行，AI 无法选择是否遵守：

- **白名单脚本入口**：只能执行下方列出的 skill 内置脚本，不能直接运行 ssh/docker/scp/sudo 或任何服务器命令。
- **远程命令白名单**：`Assert-RemoteReadCommand` 验证远程命令必须匹配只读模式（cd + 读取命令 或 docker exec 读取），不匹配即拒绝。
- **危险片段黑名单**：rm/mv/chmod/restart/kill/curl/wget 等 30+ 危险片段，出现即拒绝。
- **路径安全校验**：`Assert-SafeAbsDir`/`Assert-SafeRelDir`/`Assert-SafeLogFile` 拒绝路径穿越、shell 特殊字符。
- **参数硬上限**：Tail ≤ 5000，MaxMatches ≤ 1000，Keyword ≤ 200 字符。
- **权限模型**：`permissions.hostDir`/`permissions.docker` 控制账号可访问的日志源类型。
- **审计留痕**：每次远程读取自动写入 `logs/server-access-YYYY-MM-DD.jsonl`，7 天轮转。
- **凭据不输出**：不输出 host、SSH 用户、私钥路径、密码、token。

## 脚本入口

```text
scripts/list-targets.ps1
scripts/list-accounts.ps1    -Target <target>
scripts/list-sources.ps1     -Target <target>
scripts/list-log-files.ps1   -Target <target> -Source <source>
scripts/get-log-file.ps1     -Target <target> -Source <source> -File <file> [-Tail 200]
scripts/search-logs.ps1      -Target <target> -Source <source> -File <file> -Keyword <kw> [-MaxMatches 200]
scripts/recent-errors.ps1    -Target <target> -Source <source> -File <file> [-MaxMatches 200]
scripts/list-containers.ps1  -Target <target> -Source <source>  (仅 type:docker)
scripts/get-container-info.ps1 -Target <target> -Source <source> (仅 type:docker)
```

调用方式：`powershell -NoProfile -ExecutionPolicy Bypass -File scripts/<name>.ps1 [参数]`

配置文件：`scripts/targets.local.json`（不进 Git）。
审计日志：`logs/server-access-*.jsonl`（不进 Git）。

## 围栏以内（AI 自由发挥）

在上述围栏保护下，AI 自行决定：

- 查什么目标、什么日志源、什么文件
- 用什么关键词搜索
- 怎么跟用户沟通
- 怎么总结和脱敏日志内容
- 怎么判断错误原因
- 怎么引导用户提供更多上下文
