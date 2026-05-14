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

```powershell
git commit -m "Add <skill-name> skill"
```

更新已有 skill：

```powershell
git commit -m "Update <skill-name> skill"
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
