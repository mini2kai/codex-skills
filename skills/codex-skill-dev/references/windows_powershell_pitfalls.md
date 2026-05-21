# Windows 和 PowerShell 避坑

本仓库主要在 Windows PowerShell 中开发。以下问题已经在实际开发中发生过。

## 不使用 `&&`

某些 PowerShell 版本不支持：

```powershell
git add . && git commit -m "msg"
```

改为分开执行：

```powershell
git add .
git commit -m "msg"
```

## 避免 UTF-8 BOM

`Set-Content -Encoding UTF8` 可能写出 BOM，导致：

```text
No YAML frontmatter found
Unexpected UTF-8 BOM
```

写完后统一转无 BOM UTF-8：

```powershell
$encoding = [System.Text.UTF8Encoding]::new($false)
$text = [System.IO.File]::ReadAllText($path)
[System.IO.File]::WriteAllText($path, $text, $encoding)
```

## 防止 `$skill-name` 被展开

PowerShell 双引号和部分命令会把 `$skill-name` 识别成变量，可能变成 `-name`。

处理方式：

- 写 YAML 时使用单引号 here-string。
- 写完检查 `agents/openai.yaml`。
- `default_prompt` 必须保留 `Use $skill-name ...`。

## `apply_patch` 可能不可用

本机曾出现：

```text
Access is denied.
```

处理规则：

1. 优先尝试 `apply_patch`。
2. 如果即使提权也失败，改用 PowerShell 原生文件写入。
3. 写入范围必须限定在目标 skill、`README.md`、`manifest.json`、`scripts/install.ps1` 等明确文件。
4. 写完统一转无 BOM UTF-8。

## 删除目录前校验路径

删除 `__pycache__` 或临时目录前必须确认目标路径在预期目录内：

```powershell
$target = Resolve-Path -LiteralPath '<target>'
$root = Resolve-Path -LiteralPath '<expected-root>'
if (-not $target.Path.StartsWith($root.Path, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "Refusing to delete outside expected root: $($target.Path)"
}
Remove-Item -LiteralPath $target.Path -Recurse -Force
```

## `py_compile` 会生成缓存

运行：

```powershell
python -m py_compile scripts/*.py
```

会生成 `__pycache__`。验证结束后必须清理。
