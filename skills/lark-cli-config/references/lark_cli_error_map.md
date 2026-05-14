# lark-cli 常见错误处理

## No user logged in

含义：当前没有 user token，只有 bot/tenant identity。

处理：运行 `scripts/auth_manager.py login --domain docs,wiki,drive`，完成后再运行 `scripts/auth_manager.py status`。

## need_user_authorization

含义：当前操作需要 user 授权。

处理：启动 device login，授权完成后使用 `--as user` 重试。

## missing scope

含义：当前 token 没有目标 API 所需 scope。

处理：展示 CLI 输出中的 exact scopes；如果 CLI 给出 app authorization URL，要求使用者打开并批准后重试一次。

## app authorization URL

含义：应用后台或用户授权缺少权限。

处理：展示完整 URL，等待使用者完成授权；不要自己猜 scope。

## stale fetch after update

含义：update 后立即 fetch 可能读到旧内容。

处理：串行再 fetch 一次，不要并行 update/fetch。

## proxy warning

含义：代理提示不一定阻塞。

处理：只有在连接失败或凭据异常时才作为 blocker 报告。
