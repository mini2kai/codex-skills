# 验证清单

开发或更新 skill 后按顺序执行。

下面命令里的 `<repo-root>` 指正在开发的 skills 仓库根目录。`skill_preflight.py` 和 `validate_skill_repo.py` 来自当前 `skill-dev` skill 自身的 `scripts/` 目录，不要求目标仓库也安装 `skill-dev`。

## 基础校验

```powershell
python $HOME\.codex\skills\.system\skill-creator\scripts\quick_validate.py <repo-root>\skills\<skill-name>
```

期望：

```text
Skill is valid!
```

## manifest 校验

```powershell
python -m json.tool <repo-root>\manifest.json
```

如果出现 `Unexpected UTF-8 BOM`，先转无 BOM UTF-8。

同时确认目标 skill 条目包含 `version`，且为 `x.y.z` 格式；新增 skill 初始为 `0.1.0`，更新后按影响范围递增。

## Python 脚本语法检查

```powershell
python -m py_compile <script1.py> <script2.py>
```

检查后清理 `__pycache__`。

## PyPI 包校验

如果修改了 `packages/m2k-skills-tools` 或需要引导 PyPI 发布，额外执行：

```powershell
python -m pip index versions m2k-skills-tools
uv build packages\m2k-skills-tools
uvx twine check packages\m2k-skills-tools\dist\*
```

确认 `dist/` 中只有当前版本的 `m2k_skills_tools-<version>.tar.gz` 和 `m2k_skills_tools-<version>-py3-none-any.whl`。如果存在旧版本 dist 文件，发布前先删除并重建。

## skill 预检脚本

```powershell
python .\scripts\skill_preflight.py --repo-root <repo-root> --skill <skill-name>
```

## 仓库级校验脚本

```powershell
python .\scripts\validate_skill_repo.py --repo-root <repo-root> --skill <skill-name>
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
