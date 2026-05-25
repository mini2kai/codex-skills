---
name: server-docker-logs-readonly
description: "本地脚本白名单模式的服务器日志只读查询。用于按配置读取服务器绝对目录日志，并保留 Docker 容器内日志作为备用方案。配置文件位于 skill 自身 scripts/targets.local.json；Codex 只能执行 skill 内置脚本，不能直接运行 ssh、docker、docker exec、sudo 或任何服务器命令。"
---

# 服务器日志只读查询

## 触发规则

当用户要查看服务器日志时使用本 skill。优先读取服务器上 `pwd` 得到的绝对日志目录；只有配置为 `type: "docker"` 且账号 `permissions.docker=true` 的日志源，才允许使用 Docker 备用方案。

## 绝对边界

禁止：
- 不运行 `ssh`, `docker`, `docker exec`, `docker compose`, `scp`, `sftp`, `rsync`, `sudo` 或任何直接服务器/容器命令。
- 不向用户索要服务器 host、SSH 用户、端口、私钥路径、密码或 token。
- 不输出 `scripts/targets.local.json` 下的真实连接信息。
- 不修改服务器状态、容器状态、文件、权限、服务或 Docker 资源。

允许：
- 只执行下方白名单脚本。
- 解析脚本返回的 JSON，总结日志并脱敏。

## 文件位置

通用脚本和配置文件随 skill 一起下载：

```text
skills/server-docker-logs-readonly/scripts/
skills/server-docker-logs-readonly/scripts/targets.local.json
```

公开仓库里的配置只放示例数据。安装后，使用者在自己本机的 skill 目录中编辑该配置；如果在本仓库开发目录调试，不能提交填过真实信息的 `targets.local.json`。

本地审计日志自动写入并保留 7 天：

```text
skills/server-docker-logs-readonly/logs/server-access-YYYY-MM-DD.jsonl
```

审计日志记录所有服务器读取操作的时间、目标、账号别名、日志源、读取动作和只读远程命令；`logs/` 目录不提交到 Git。

## 脚本白名单

```text
skills/server-docker-logs-readonly/scripts/list-targets.ps1
skills/server-docker-logs-readonly/scripts/list-accounts.ps1
skills/server-docker-logs-readonly/scripts/list-sources.ps1
skills/server-docker-logs-readonly/scripts/list-log-files.ps1
skills/server-docker-logs-readonly/scripts/get-log-file.ps1
skills/server-docker-logs-readonly/scripts/search-logs.ps1
skills/server-docker-logs-readonly/scripts/recent-errors.ps1
skills/server-docker-logs-readonly/scripts/list-containers.ps1
skills/server-docker-logs-readonly/scripts/get-container-info.ps1
```

`list-containers.ps1` 和 `get-container-info.ps1` 只能用于 `type: "docker"` 的日志源。不要直接调用 `common.ps1` 或 `ssh_run.py`。

## 配置模型

配置文件是标准 JSON。字段含义写在 `_fieldDescriptions` 中；真实查询只读取 `targets`。

核心结构：
- `targets`：服务器目标集合。
- `accounts`：同一服务器下的多个 SSH 账号。
- `permissions.hostDir`：是否允许读取服务器绝对目录。
- `permissions.docker`：是否允许使用 Docker 备用方案。
- `sources`：日志源集合。
- `type: "host_dir"`：读取服务器绝对目录 `absDir`。
- `type: "docker"`：读取容器 `container` 内的相对目录 `logDir`。

## 标准流程

1. 用 `list-targets.ps1` 查看目标。
2. 用 `list-accounts.ps1 -Target <target>` 查看账号和权限。
3. 用 `list-sources.ps1 -Target <target>` 查看日志源。
4. 用 `list-log-files.ps1 -Target <target> -Source <source>` 列出文件。
5. 指定 `File` 后，执行读取或搜索脚本。
6. 总结日志前先脱敏 secret、token、cookie、Authorization header 等信息。

## 命令模板

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skills/server-docker-logs-readonly/scripts/list-targets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File skills/server-docker-logs-readonly/scripts/list-accounts.ps1 -Target example-dev
powershell -NoProfile -ExecutionPolicy Bypass -File skills/server-docker-logs-readonly/scripts/list-sources.ps1 -Target example-dev
powershell -NoProfile -ExecutionPolicy Bypass -File skills/server-docker-logs-readonly/scripts/list-log-files.ps1 -Target example-dev -Source app-host-log
powershell -NoProfile -ExecutionPolicy Bypass -File skills/server-docker-logs-readonly/scripts/get-log-file.ps1 -Target example-dev -Source app-host-log -File app.log -Tail 200
powershell -NoProfile -ExecutionPolicy Bypass -File skills/server-docker-logs-readonly/scripts/search-logs.ps1 -Target example-dev -Source app-host-log -File app.log -Keyword ERROR -MaxMatches 200
powershell -NoProfile -ExecutionPolicy Bypass -File skills/server-docker-logs-readonly/scripts/recent-errors.ps1 -Target example-dev -Source app-host-log -File app.log -MaxMatches 200
```

## 参数规则

- `Target`：只能使用 `list-targets.ps1` 返回的目标别名。
- `Source`：只能使用 `list-sources.ps1` 返回的日志源别名。
- `File`：必须显式指定，只能使用 `list-log-files.ps1` 返回的文件名。
- `Tail`：默认 200，最大 5000。
- `MaxMatches`：默认 200，最大 1000。

## 失败处理

`config_missing`, `target_not_found`, `account_not_found`, `source_not_found`, `account_permission_denied`, `file_required`, `script_command_failed`, `script_missing` 都只能报告脚本错误和下一步，不能绕过脚本直连服务器。

## 最终反馈

只报告使用的脚本、目标别名、日志源、账号别名、日志文件、行数/匹配数、关键片段和结论。不输出真实 host、SSH 用户、私钥路径、密码、token 或未脱敏的大段日志。
