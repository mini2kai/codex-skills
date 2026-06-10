# 仓库约定

## 目录结构

```text
skills/<skill-name>/
├── SKILL.md          # 围栏规则 + 脚本入口（给 AI）
├── DESIGN.md         # 设计理念和实现思路（给人）
├── references/       # 事实性配置/格式说明
└── scripts/          # 围栏代码 + 测试
```

不再创建 `agents/` 目录。

## 命名

- 目录名、manifest 条目名、SKILL.md frontmatter `name` 三者一致。
- 目录名用小写 kebab-case。

## 版本

每个 skill 在 `manifest.json` 中有独立 `version`（`x.y.z`）：

- 新 skill：`0.1.0`
- patch：围栏逻辑不变的小修（文档、提示）
- minor：新增兼容能力、脚本参数、围栏规则
- major：改名、移除能力、破坏性行为变化

## PyPI 管理器

`packages/m2k-skills-tools` 的版本独立于 skill 版本，用 `sync_package_version.py` 同步。已发布版本不可覆盖。

## 文件编码

所有文本文件统一无 BOM UTF-8。

## Git

- 提交信息中文
- 推送目标：`origin main`
- commit/push 前需用户确认
