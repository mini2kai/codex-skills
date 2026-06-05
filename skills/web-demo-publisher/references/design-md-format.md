# DESIGN.md 设计规范

## 查找顺序

1. 用户明确指定的 `DESIGN.md`。
2. 当前项目目录下的 `DESIGN.md`。
3. 当前项目父目录下的 `DESIGN.md`。
4. skill 默认设计规则。

## 推荐格式

```markdown
# Design System

## Brand
- Name: Example Brand
- Audience: engineering team
- Tone: professional, concise, technical

## Visual Style
- Overall: dark, warm, minimal
- Avoid: gradients, big rounded pills, heavy shadows

## Colors
- Background: #2b2622
- Surface: #383330
- Border: #3f3a36
- Text: #f7f5f0
- Muted text: #c9bda8
- Accent: #f7f5f0

## Typography
- Sans: Inter
- Mono: DM Mono
- Letter spacing: 0

## Components
- Cards: radius 3-4px, no drop shadow
- Buttons: compact, clear affordance
- Sections: full-width bands, no nested cards

## Layout
- Desktop: dense but readable
- Mobile: no overlapping text, no horizontal overflow

## Content Rules
- Keep copy concise
- Avoid marketing fluff
- Prefer practical examples
```

## 设计优先级

1. 用户本轮明确要求。
2. 用户提供的 `DESIGN.md`。
3. 模板结构。
4. skill 默认设计规则。

用户本轮要求与 `DESIGN.md` 冲突时，以用户本轮要求为准。不要把 `DESIGN.md` 当作必须完整复刻的页面内容；它约束视觉、交互和文案风格。

## 默认设计规则

- 页面先可用，再精修视觉。
- 避免文字重叠、横向溢出和只有单色系的视觉。
- 卡片半径不超过 8px，除非设计规范要求。
- 工具、仪表盘和业务页优先密集、克制、可扫描。
- 站点和演示需要真实视觉资产或可运行交互，不做纯空壳说明页。

