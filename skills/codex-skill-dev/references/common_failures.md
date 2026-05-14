# 常见失败和处理

## init_skill.py short_description 太短

现象：

```text
[ERROR] short_description must be 25-64 characters
```

处理：

- 检查是否已经创建半成品目录。
- 补齐 `agents/openai.yaml`、`references/`、`scripts/`。
- 下次给 `short_description` 至少 25 个字符。

## YAML frontmatter 识别失败

现象：

```text
No YAML frontmatter found
```

常见原因：文件有 UTF-8 BOM。

处理：统一转无 BOM UTF-8，然后重跑 `quick_validate.py`。

## manifest JSON 解析失败

现象：

```text
Unexpected UTF-8 BOM
```

处理：统一转无 BOM UTF-8，然后重跑：

```powershell
python -m json.tool manifest.json
```

## PowerShell 变量展开破坏 default_prompt

现象：

```yaml
default_prompt: "Use -query ..."
```

原因：`$postgres-query` 被当作变量展开。

处理：用单引号 here-string 写入，写完检查 `openai.yaml`。

## apply_patch Access is denied

现象：

```text
Access is denied.
```

处理：如果提权仍失败，改用 PowerShell 原生文件写入，并限制路径范围。

## py_compile 生成 __pycache__

现象：`skills/<skill>/scripts/__pycache__/` 出现在工作区。

处理：确认路径在目标 skill 内后删除。

## git add 权限失败

现象：

```text
Unable to create .git/index.lock: Permission denied
```

处理：按审批流程提权重试 `git add`。

## git push 网络失败

现象：

```text
Failed to connect to 127.0.0.1 port 9
```

处理：按审批流程提权重试 `git push origin main`。

## 脚本提示是英文

现象：脚本 JSON 的 `message`、`next_action` 出现英文。

处理：面向用户的消息改中文；JSON key 和命令参数保持英文。
