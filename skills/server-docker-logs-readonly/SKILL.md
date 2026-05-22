---
name: server-docker-logs-readonly
description: "本地脚本白名单模式的 Docker 容器内服务日志文件查询。用于查看 Docker 容器内的日志文件，例如 logs/MODULE_INSTANCE.log 和滚动文件 MODULE_INSTANCE.log.YYYY-MM-DD。真实服务器配置只能保留在本地 custom_script；Codex 只能执行 skill 内置的白名单脚本，不能直接运行 ssh、docker、docker exec、sudo 或任何服务器命令。"
---

# 服务器 Docker 容器日志文件查询

## 触发规则

当用户要查看服务器上 Docker 容器内的服务日志文件时使用本 skill。常见日志形态：

```text
logs/MODULE_INSTANCE.log
logs/MODULE_INSTANCE.log.2026-05-21
```

人工方式可能是 `docker exec -it <container> /bin/bash` 后进入 `logs/` 目录查看文件。Codex 不得直接执行这些命令，只能调用本 skill 内置的 wrapper 脚本。

## 绝对边界

禁止：
- 不运行 `ssh`, `docker`, `docker exec`, `docker compose`, `scp`, `sftp`, `rsync`, `sudo` 或任何直接服务器/容器命令。
- 不向用户索要服务器 host、SSH 用户、端口、私钥路径、密码或 token。
- 不输出 `custom_script/` 下的真实连接信息。
- 不修改服务器状态、容器状态、文件、权限、服务或 Docker 资源。

允许：
- 只执行下方白名单脚本。
- 解析脚本返回的 JSON，总结日志并脱敏。

## 目录结构

通用脚本随 skill 一起下载：

```text
skills/server-docker-logs-readonly/scripts/
```

真实配置只能放在本地忽略目录：

```text
custom_script/server-docker-logs-readonly/targets.local.json
```

skill 内自带一个只有示例数据的格式文件：

```text
skills/server-docker-logs-readonly/scripts/targets.local.json
```

这个文件只用于说明配置格式，不得当作真实连接配置使用。真实配置可能包含服务器地址、账号或密码，只能保存在 `custom_script/` 下，不能提交到 GitHub。

## 脚本白名单

```text
skills/server-docker-logs-readonly/scripts/list-targets.ps1
skills/server-docker-logs-readonly/scripts/list-containers.ps1
skills/server-docker-logs-readonly/scripts/get-container-info.ps1
skills/server-docker-logs-readonly/scripts/list-log-files.ps1
skills/server-docker-logs-readonly/scripts/get-log-file.ps1
skills/server-docker-logs-readonly/scripts/get-logs.ps1
skills/server-docker-logs-readonly/scripts/search-logs.ps1
skills/server-docker-logs-readonly/scripts/recent-errors.ps1
```

不要直接调用 `common.ps1` 或 `ssh_run.py`，它们只是内部公共实现。

## 配置示例

公开示例必须使用占位值，不得出现真实服务器、账号、密码或容器名。

```json
{
  "targets": {
    "example-dev": {
      "description": "示例开发服务器",
      "ssh": {
        "host": "your-host-or-ssh-alias",
        "user": "readonly-user",
        "port": 22,
        "auth": {
          "type": "password",
          "password": "replace-with-local-password"
        }
      },
      "containers": {
        "example-backend": {
          "description": "示例后端服务容器",
          "logDir": "logs",
          "logFilePrefix": "MODULE_INSTANCE.log",
          "defaultLogFile": "MODULE_INSTANCE.log"
        }
      }
    }
  }
}
```

## 标准流程

1. 理解用户要查的日志：目标别名、容器、文件、行数、关键字。
2. 检查白名单脚本和本地 `targets.local.json` 是否存在。
3. 执行白名单脚本并解析 JSON 结果。
4. 总结日志前先脱敏 secret、token、cookie、Authorization header 等信息。

## 命令模板

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skills/server-docker-logs-readonly/scripts/list-targets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File skills/server-docker-logs-readonly/scripts/list-log-files.ps1 -Target example-dev -Container example-backend
powershell -NoProfile -ExecutionPolicy Bypass -File skills/server-docker-logs-readonly/scripts/get-log-file.ps1 -Target example-dev -Container example-backend -File MODULE_INSTANCE.log -Tail 200
powershell -NoProfile -ExecutionPolicy Bypass -File skills/server-docker-logs-readonly/scripts/search-logs.ps1 -Target example-dev -Container example-backend -File MODULE_INSTANCE.log -Keyword ERROR -MaxMatches 200
powershell -NoProfile -ExecutionPolicy Bypass -File skills/server-docker-logs-readonly/scripts/recent-errors.ps1 -Target example-dev -Container example-backend -File MODULE_INSTANCE.log -MaxMatches 200
```

## 参数规则

- `Target`：只能使用 `list-targets.ps1` 返回的目标别名。
- `Container`：只能使用本地配置允许的容器名。
- `File`：只能使用 `list-log-files.ps1` 返回的文件名，且必须匹配 `logFilePrefix`。
- `Tail`：默认 200，最大 5000。
- `MaxMatches`：默认 200，最大 1000。

## 失败处理

`config_missing`, `target_not_found`, `container_not_allowed`, `log_file_not_allowed`, `script_command_failed`, `script_missing` 都只能报告脚本错误和下一步，不能绕过脚本直连服务器。

## 最终反馈

只报告使用的脚本、目标别名、容器名、日志文件、行数/匹配数、关键片段和结论。不输出真实 host、SSH 用户、私钥路径、密码、token 或未脱敏的大段日志。
