# Skill 格式规范

## SKILL.md

frontmatter 只写必要字段：

```yaml
---
name: skill-name
description: 清晰说明能力和触发场景。Use when ...
---
```

要求：

- `name` 与目录名一致。
- `description` 必须包含“什么时候使用”，因为这是触发依据。
- 主体用中文，命令和参数保持英文。
- 不在正文写空泛的“when to use”，触发信息应放进 `description`。
- 主体控制在可读范围内，细节放 `references/`。

推荐结构：

```text
## 触发规则
## 执行入口
## 标准流程
## 规则导航
## 安全底线
## 最终反馈
```

## agents/openai.yaml

推荐格式：

```yaml
interface:
  display_name: "Skill Display Name"
  short_description: "中文简短说明，25-64 字符"
  default_prompt: "Use $skill-name 中文默认提示。"

policy:
  allow_implicit_invocation: true
```

注意：

- `default_prompt` 必须保留 `$skill-name`。
- PowerShell 会展开 `$xxx`，写完必须检查是否被误改。
- `short_description` 长度不足会导致初始化失败。

## references

用于按需读取的细节资料。每个文件直接由 `SKILL.md` 引用，不要深层嵌套。

适合放：

- 仓库规范。
- 错误处理表。
- 长流程清单。
- 常用命令和模板。

## scripts

用于可重复、容易出错或需要结构化输出的操作。

要求：

- 输出 JSON。
- 面向用户的 `message`、`next_action` 用中文。
- 参数名、JSON key、命令保持英文。
- 不执行高风险操作，除非 skill 明确要求并有确认流程。

## 不要创建

skill 内不要创建这些额外说明文档：

- `README.md`
- `CHANGELOG.md`
- `INSTALLATION_GUIDE.md`
- `QUICK_REFERENCE.md`

这些内容应进入 `SKILL.md` 或 `references/`。
