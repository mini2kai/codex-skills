# 访问诊断

## 诊断顺序

1. 端口是否监听：`localhost:9999` 是否有进程。
2. 本地 HTTP 是否可访问：`http://localhost:9999/` 是否返回 2xx/3xx。
3. `data/runtime.local.json` 是否记录了当前 PID、端口和启动命令。
4. cpolar 是否安装、服务是否运行、本地面板是否可访问。
5. cpolar 隧道是否指向当前端口。
6. 公网 URL 是否返回 2xx/3xx。

## 常见问题

- `502 Bad Gateway`：本地服务未启动，或 cpolar 隧道仍指向旧端口。
- `403 Host blocked`：Vite dev server 未允许 cpolar 域名；优先改用 `vite preview`。
- 公网很慢：可能误用了 `npm run dev`；构建后用 `vite preview`。
- 公网域名变化：免费版正常现象；重新读取日志或面板。
- 本地可访问但公网失败：报告本地成功，并把失败范围限定在 cpolar 或公网链路。
- Vite preview 失败但 `dist/index.html` 存在：fallback 到静态服务器后重新验证本地地址。

## 回复口径

- 本地成功、公网失败：`本地发布已完成；公网暂不可用，原因可能是 ...`。
- 构建失败：指出命令、退出码和关键错误，不继续伪装发布成功。
- 端口冲突：说明已尝试停止旧进程；若仍冲突，报告 PID 和占用端口。
