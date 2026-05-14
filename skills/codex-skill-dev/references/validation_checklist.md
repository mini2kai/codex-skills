# 验证清单

开发或更新 skill 后按顺序执行。

## 基础校验

```powershell
python C:\Users\lzsj\.codex\skills\.system\skill-creator\scripts\quick_validate.py C:\Users\lzsj\all\codex-skills\skills\<skill-name>
```

期望：

```text
Skill is valid!
```

## manifest 校验

```powershell
python -m json.tool C:\Users\lzsj\all\codex-skills\manifest.json
```

如果出现 `Unexpected UTF-8 BOM`，先转无 BOM UTF-8。

## Python 脚本语法检查

```powershell
python -m py_compile <script1.py> <script2.py>
```

检查后清理 `__pycache__`。

## skill 预检脚本

```powershell
python skills\codex-skill-dev\scripts\skill_preflight.py --repo-root . --skill <skill-name>
```

## 仓库级校验脚本

```powershell
python skills\codex-skill-dev\scripts\validate_skill_repo.py --repo-root . --skill <skill-name>
```

## 行为测试

根据 skill 类型选择一到两个关键路径：

- 安全拒绝路径。
- 缺少依赖路径。
- 缺少配置路径。
- 只读或 dry-run 路径。

不要为了测试执行生产写操作。

## Git 检查

```powershell
git diff --stat
git status --short
```

提交前检查是否包含：

- `__pycache__`
- `.env`
- 临时凭据
- 数据库导出
- 大型无关文件
