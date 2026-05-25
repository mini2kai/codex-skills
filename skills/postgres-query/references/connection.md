# PostgreSQL 连接引导

当连接信息缺失、不明确，或分散在项目配置中时读取本文件。

## 查找顺序

1. 优先使用用户本轮明确提供的临时 DSN。
2. 其次使用用户明确指定的本机连接别名：`--profile <profile>`。
3. 再使用 `POSTGRES_DSN`。
4. 再使用完整的 PG 环境变量：
   - `PGHOST`
   - `PGPORT`，默认 `5432`
   - `PGDATABASE`
   - `PGUSER`
   - `PGPASSWORD`
   - `PGSSLMODE`，仅在需要 SSL 时使用
5. 最后使用 `scripts/connections.local.json` 的 `defaultProfile`。
6. 只有当用户明确要求使用当前项目连接时，才检查项目中的 `.env`、`.env.local`、`.env.development` 或配置说明。不要打印密码。
7. 如果目标库、环境或连接方式仍不明确，先询问用户，不要尝试猜测。

## 本机多连接配置

配置文件位于 skill 安装目录：

```text
skills/postgres-query/scripts/connections.local.json
```

`connections.local.json` 直接内置示例数据，在 `profiles` 下维护多个连接别名。推荐用 `passwordEnv` 保存密码环境变量；如需写 `password`，公开仓库必须保留占位值，不要提交真实密码。

示例：

```json
{
  "defaultProfile": "example-readonly-db",
  "profiles": {
    "example-readonly-db": {
      "description": "开发库",
      "host": "your-db-host",
      "port": 5432,
      "dbname": "your_db",
      "user": "readonly_user",
      "passwordEnv": "PGPASSWORD_EXAMPLE_READONLY_DB",
      "sslmode": "disable"
    }
  }
}
```

PowerShell 设置当前会话密码环境变量：

```powershell
$env:PGPASSWORD_EXAMPLE_READONLY_DB = '<your-password>'
```

使用连接别名：

```powershell
python scripts/pg_profiles.py
python scripts/pg_query.py --profile example-readonly-db --sql "select current_database(), current_user, now()" --limit 20
```

## 连接信息不明确时的话术

```text
我需要临时的 PostgreSQL 连接信息才能查询。请提供以下任一方式：
1. 临时 DSN：postgresql://user:password@host:5432/dbname
2. 分项信息：host、port、database、username、password、sslmode（如需要）

建议使用只读账号；如果是生产库，请确认你确实希望查询该环境。我不会把连接信息写入 skill、仓库或最终结果。
```

## 敏感信息处理

- 不把真实凭据写入仓库文件；长期复用时优先把密码放到环境变量，并在 `connections.local.json` 里配置 `passwordEnv`。
- 不在最终回答中展示完整 DSN。
- 汇总命令输出时必须隐藏密码。
- 重复查询时优先建议用户使用环境变量。
- 不提交 `.env`、真实密码、临时凭据文件或数据库导出文件。

## 连接验证

凭据可用后，可以先执行轻量只读验证：

```sql
select current_database(), current_user, now();
```

只在必要时报告数据库名和用户名；如果上下文敏感，改为说明“连接验证通过”。
