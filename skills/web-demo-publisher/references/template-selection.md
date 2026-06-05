# 模板选择和项目识别

## 项目识别

- Slidev：存在 `slides.md`，或 `package.json` 包含 `@slidev/cli`、`slidev` 脚本。
- Vite：`package.json` 包含 `vite` 依赖或 `build` 脚本。
- 静态 dist：存在 `dist/index.html`。
- 普通 HTML：存在 `index.html`。
- 未知项目：先问一个关键问题，或按用户意图生成新模板项目。

## 发布策略

- Slidev：`npm run build`，然后 `npx vite preview --host 127.0.0.1 --port 9999`。
- Vite：`npm run build`，然后 `npx vite preview --host 127.0.0.1 --port 9999`。
- 静态 dist：用内置静态服务器发布 `dist/`。
- 普通 HTML：用内置静态服务器发布项目根目录。
- 未知：若用户要新建，选择模板；若用户要发布现有项目，询问入口文件或构建命令。

## 内置模板

- `landing-product`：产品、项目、工具介绍页。
- `slidev-talk`：Slidev 技术分享演示。
- `tool-single-page`：无需构建的单页小工具。

每个模板目录必须包含 `template.json`：

```json
{
  "name": "tool-single-page",
  "type": "static-html",
  "requiresNode": false,
  "entry": "index.html",
  "publishMode": "static-server",
  "bestFor": ["单页小工具"],
  "expectedFiles": ["index.html"]
}
```

新增模板时先补 metadata，再让 `generate-from-template.ps1` 自动复制模板内容；不要复制 `template.json` 到用户项目。

## 自动选择

- “官网”“产品介绍”“项目介绍” -> `landing-product`。
- “PPT”“slides”“分享页”“技术分享” -> `slidev-talk`。
- “计算器”“查询工具”“小工具” -> `tool-single-page`。
- “作品集”“简历页” -> 先用 `landing-product` 改写为个人作品集结构。
- “仪表盘”“看板” -> 先用 `tool-single-page` 改写为数据面板结构。

模板是起点，不是终点。生成后应根据用户文本、目标受众和 `DESIGN.md` 改标题、区块、交互和视觉。
