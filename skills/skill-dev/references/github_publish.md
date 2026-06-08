# GitHub 发布流程

## 提交前

确认工作区只包含本次目标改动：

```powershell
git status --short
git diff --stat
```

必要时查看关键 diff：

```powershell
git diff -- README.md manifest.json scripts/install.ps1
```

## 暂存

PowerShell 中分步执行：

```powershell
git add README.md manifest.json scripts/install.ps1 skills/<skill-name>
```

如果 `git add` 报：

```text
Unable to create .git/index.lock: Permission denied
```

按审批流程提权重试，不要手动删除 lock，除非确认没有其他 git 进程。

## 提交

提交信息必须使用中文，并简要写清楚修改内容。

```powershell
git commit -m "新增 <skill-name> skill"
```

更新已有 skill：

```powershell
git commit -m "更新 <skill-name> skill 指引"
```

## 推送

```powershell
git push origin main
```

如果因为网络、代理或沙箱失败，按审批流程提权重试。

## 完成确认

```powershell
git status --short
git rev-parse --short HEAD
git log -1 --oneline
```

最终反馈包括：

- commit hash
- push 目标
- 是否工作区干净

## PyPI 发布引导

如果本次提交涉及 `packages/m2k-skills-tools` 或用户要求提交 PyPI，GitHub 推送后继续引导 PyPI 发布。PyPI 是为 skill 安装、更新、版本对比服务的管理器发布渠道。

发布前检查：

```powershell
python -m pip index versions m2k-skills-tools
python skills\skill-dev\scripts\sync_package_version.py --repo-root . --bump patch
uv build packages\m2k-skills-tools
uvx twine check packages\m2k-skills-tools\dist\*
```

上传命令模板：

```powershell
$env:UV_PUBLISH_TOKEN = "pypi-你的新PyPI-token"
uv publish C:\Users\lzsj\all\codex-skills\packages\m2k-skills-tools\dist\m2k_skills_tools-<version>.tar.gz C:\Users\lzsj\all\codex-skills\packages\m2k-skills-tools\dist\m2k_skills_tools-<version>-py3-none-any.whl
Remove-Item Env:\UV_PUBLISH_TOKEN
```

必须把 `<version>` 替换为当前包版本；不要提醒用户上传已经发布过的旧版本文件，例如 `0.1.0`。上传后验证：

```powershell
python -m pip index versions m2k-skills-tools
uvx --from m2k-skills-tools==<version> m2k-skills-tools --help
```
