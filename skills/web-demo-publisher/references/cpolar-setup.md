# cpolar 可选发布

## 模式

- `auto`：默认。检测到 cpolar 就尝试外网地址，失败也保留本地预览。
- `required`：用户明确要求必须外网可访问；失败时报告阻塞原因。
- `off`：完全跳过 cpolar，只返回本地地址。

## 推荐隧道

```yaml
tunnels:
  public-9999:
    proto: http
    addr: "9999"
    bind_tls: both
    start_type: enable
```

不要写入或回显用户 `authtoken`。如果需要配置 cpolar，只给用户可审查的配置片段和影响说明。

## 公网地址

优先从本地面板 `http://localhost:9200/` 或 `http://127.0.0.1:9200/` 提取当前 URL；找不到时再从 cpolar 日志中提取最近的 `https://*.cpolar.top`，并筛选本地地址为 `localhost:9999` 或 `127.0.0.1:9999` 的记录。仍找不到时提示用户打开本地面板查看。

免费版 cpolar 的公网域名可能在服务重启、电脑重启、隧道重建或网络变化后改变。每次发布后都重新检测当前 URL，不承诺长期固定。

## 敏感信息

最终回复只报告：cpolar 是否可用、公网 URL、HTTP 状态和诊断结论。不要贴出原始日志行、认证行、token、邮箱或密码。
