---
name: web-demo-publisher
description: Generate, iterate, preview, publish, and diagnose web demos, Slidev decks, Vite apps, static sites, landing pages, portfolios, and small web tools. Use when the user wants guided web creation, DESIGN.md-based styling, localhost:9999 previews, optional cpolar public URLs, local/external sharing, template-based web generation, or troubleshooting public access failures such as 502/403/slow cpolar links.
---

# Web Demo Publisher

## 触发规则

用户要生成网页、发布当前 Web 项目、启动 Slidev 演示、固定预览到 `localhost:9999`、获取 cpolar 外网地址、诊断公网访问失败，或提到 `DESIGN.md`、`cpolar`、`slides`、`9999`、本地预览、外网分享时，使用本 skill。

## 执行入口

- 新建网页：先判断模板类型，必要时只问一个关键问题；再复制 `assets/templates/<template>/` 或直接在用户项目中生成页面。
- 发布已有项目：运行 `scripts/publish.ps1 -ProjectPath <path> -Port 9999 -UseCpolar auto`。
- 只本地预览：运行 `scripts/publish.ps1 -ProjectPath <path> -UseCpolar off`。
- 停止预览：运行 `scripts/stop-port.ps1 -Port 9999`；脚本会优先读取 `data/runtime.local.json` 停止本 skill 启动的进程。
- 只获取外网地址：运行 `scripts/get-cpolar-url.ps1 -Port 9999`，再用 `scripts/validate-public-url.ps1 -Url <url>` 验证。
- 诊断问题：运行 `scripts/diagnose.ps1 -ProjectPath <path> -Port 9999 -PublicUrl <url>`。

所有脚本输出 JSON。最终回复只摘取用户需要的地址、状态、PID、停止命令和诊断结论；不要原样贴出可能包含认证信息的日志。

## 标准流程

1. 判断用户状态：`new_project`、`clarifying`、`designing`、`generating`、`previewing`、`iterating`、`publishing`、`diagnosing`。
2. 信息不足时只问一个最影响方向的问题；若上下文足够，直接做合理选择并生成可运行第一版。
3. 生成或修改网页前查找 `DESIGN.md`：用户指定路径、当前项目、父目录、再退回 skill 默认规则。详见 `references/design-md-format.md`。
4. 根据需求选择模板或项目类型。详见 `references/template-selection.md`。
5. 先保证本地可运行：默认停止旧 `9999` 服务，构建项目，启动本地预览，验证 `http://localhost:9999/`。
6. 本地预览成功后写入 `data/runtime.local.json`，记录端口、PID、命令和项目路径，供停止与诊断使用。
7. cpolar 默认 `auto`：先尝试本地面板，再读取日志；可用则提取并验证公网 URL，不可用不阻塞本地成功。详见 `references/cpolar-setup.md`。
8. 如果公网失败但本地成功，明确区分“本地发布成功”和“外网暂不可用”，并给出诊断原因。

## 发布规则

- 默认端口是 `9999`；用户明确指定端口时才覆盖。
- 发布新内容前先停止目标端口旧服务。
- Slidev/Vite 外网分享优先使用 `npm run build` 加 `npx vite preview --host 127.0.0.1 --port 9999`。
- 如果项目有 `preview` script，优先使用项目自己的 preview 命令并追加 host/port 参数。
- 如果 `vite preview` 未通过本地验证，但存在 `dist/index.html`，自动 fallback 到内置静态服务器。
- 普通 `index.html` 或已有 `dist/index.html` 用脚本内置的 PowerShell 静态服务器启动。
- Node 版本可用时优先 Node 20；不要因为无法切换 Node 就停止，除非构建确实失败。
- 依赖未安装时可执行 `npm install`，但不要覆盖用户的 package 管理策略；发现 `pnpm-lock.yaml` 或 `yarn.lock` 时优先提示并按现有工具执行。

## 生成规则

- 第一版优先做到：能运行、结构完整、内容合理、移动端不崩、可继续迭代。
- 模板只提供结构起点；视觉风格以用户本轮要求和 `DESIGN.md` 为准。
- 每个模板应包含 `template.json`，说明 `type`、`entry`、`publishMode`、`bestFor` 和 `expectedFiles`。
- 不复制未授权第三方模板代码、图片或资产；在线来源只能作为布局和交互参考，除非授权明确允许复用。
- 不创建营销式空壳页；用户要工具、演示或站点时，第一屏就是可用体验或真实内容。

## 脚本导航

- `scripts/detect-project.ps1`：识别 Slidev、Vite、静态 dist、普通 HTML 或未知项目。
- `scripts/detect-design-md.ps1`：按优先级查找 `DESIGN.md` 并返回摘要。
- `scripts/generate-from-template.ps1`：从内置模板生成新项目。
- `scripts/stop-port.ps1`：停止指定端口进程。
- `scripts/start-local-preview.ps1`：启动 Vite preview 或静态服务器。
- `scripts/publish.ps1`：完整发布流水线。
- `scripts/detect-cpolar.ps1`：检测 cpolar 命令、服务、本地面板和配置。
- `scripts/get-cpolar-url.ps1`：从 cpolar 日志提取当前公网 URL。
- `scripts/validate-public-url.ps1`：验证公网 URL 是否可访问。
- `scripts/diagnose.ps1`：本地端口、localhost、cpolar 和公网综合诊断。
- `scripts/test-skill.ps1`：运行本 skill 自测，覆盖脚本语法、模板、发布、停止、DESIGN.md digest 和 cpolar 日志提取。

## 规则导航

- `references/design-md-format.md`：`DESIGN.md` 查找、格式和设计优先级。
- `references/template-selection.md`：项目类型识别、模板选择和生成策略。
- `references/cpolar-setup.md`：cpolar 可选发布、免费版域名变化和敏感信息规则。
- `references/troubleshooting.md`：502、403、慢访问、端口不一致等诊断表。
- `references/getdesign-source.md`：在线设计参考源的使用边界。

## 安全底线

- 不打包、不请求、不回显 cpolar `authtoken`、邮箱、密码、cookie 或认证日志。
- 读取 cpolar 日志时只提取公网 URL、端口和非敏感状态；最终回复不要贴原始日志。
- 修改 cpolar 配置、重启 Windows 服务或需要管理员权限的动作，先说明影响并等待用户明确同意。
- 外网成功不是本地发布成功的前提；cpolar 失败时保留本地预览地址。
- 不回退用户已有项目改动；生成文件前先检查目标目录，避免覆盖同名文件，除非用户明确要求覆盖。
- 运行态文件只写入 `data/*.local.json`，不要提交到 Git。

## 最终反馈

完成后用中文简洁报告：

- 本地地址，例如 `http://localhost:9999/`。
- 外网地址；没有则说明 cpolar 状态和下一步。
- 服务 PID、端口、预览模式和停止命令。
- 若失败，区分本地失败、构建失败、cpolar 失败、公网验证失败，并给出最可能原因。
