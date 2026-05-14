# Windows 中文 Markdown 上传指南

## 固定规则

- 中文 markdown 上传前必须保存为 UTF-8 文件。
- 使用 `--markdown "@file.md"` 传入文件。
- 避免 PowerShell stdin、pipeline 或临时字符串拼接上传中文正文。
- 如果本地文件中已经出现 `?` 或乱码，不要上传。

## 推荐流程

1. 使用 UTF-8 安全方式写入本地 markdown。
2. 用 wrapper 或脚本检查文件存在、大小和 UTF-8 可读。
3. 执行 `docs +create` 或 `docs +update --mode overwrite`。
4. 执行 `docs +fetch` 验证标题和主要章节。

## 异常恢复

- 如果 fetch 后发现乱码，优先用正确 UTF-8 文件 full overwrite。
- 不要用增量 stdin patch 修复已乱码内容。
- Feishu table/prose 中避免裸 `<code>`、`<page_code>`、`<column>`，使用 `{code}`、`{page_code}`、`{column}`。
