# PostgreSQL 连接引导

当连接信息缺失、不明确，或分散在项目配置中时读取本文件。

## 查找顺序

1. 优先使用用户本轮明确提供的临时 DSN。
2. 其次使用 `POSTGRES_DSN`。
3. 再使用完整的 PG 环境变量：
   - `PGHOST`
   - `PGPORT`，默认 `5432`
   - `PGDATABASE`
   - `PGUSER`
   - `PGPASSWORD`
   - `PGSSLMODE`，仅在需要 SSL 时使用
4. 只有当用户明确要求使用当前项目连接时，才检查项目中的 `.env`、`.env.local`、`.env.development` 或配置说明。不要打印密码。
5. 如果目标库、环境或连接方式仍不明确，先询问用户，不要尝试猜测。

## 连接信息不明确时的话术

```text
我需要临时的 PostgreSQL 连接信息才能查询。请提供以下任一方式：
1. 临时 DSN：postgresql://user:password@host:5432/dbname
2. 分项信息：host、port、database、username、password、sslmode（如需要）

建议使用只读账号；如果是生产库，请确认你确实希望查询该环境。我不会把连接信息写入 skill、仓库或最终结果。
```

## 敏感信息处理

- 不把凭据写入文件。
- 不在最终回答中展示完整 DSN。
- 汇总命令输出时必须隐藏密码。
- 重复查询时优先建议用户使用环境变量。
- 不提交 `.env`、临时凭据文件或数据库导出文件。

## 连接验证

凭据可用后，可以先执行轻量只读验证：

```sql
select current_database(), current_user, now();
```

只在必要时报告数据库名和用户名；如果上下文敏感，改为说明“连接验证通过”。
