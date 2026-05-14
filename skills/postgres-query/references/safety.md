# PostgreSQL 安全策略

执行 SQL 或响应可能修改数据/结构的请求前读取本文件。

## 默认允许执行

默认只执行只读操作：

- `SELECT`
- 只读 `WITH`
- `SHOW`
- information schema 或 PostgreSQL catalog 元数据查询
- 不带 `ANALYZE` 的 `EXPLAIN`

样例数据查询必须限制行数，除非查询本身是预期返回少量行的聚合结果。

## 默认禁止执行

以下操作不得由本 skill 直接执行：

- `INSERT`
- `UPDATE`
- `DELETE`
- `TRUNCATE`
- `DROP`
- `ALTER`
- `CREATE`
- `GRANT`
- `REVOKE`
- `VACUUM`
- `CALL`
- `DO`
- `COPY`
- `MERGE`
- `REFRESH MATERIALIZED VIEW`
- `EXPLAIN ANALYZE`
- 包含写入的多语句事务

遇到风险请求时，只生成 SQL。必须附带影响范围、执行前检查、执行后验证和回滚思路。明确要求用户在已授权的数据库工具或发布流程中自行执行。

## 风险操作回复模板

```text
这个请求会修改数据库。我不会直接执行。下面是可由你在授权工具中执行的 SQL：

[SQL]

影响范围：...
执行前检查：...
执行后验证：...
回滚思路：...
```

## 结果展示

- 只展示必要字段和必要行数。
- 除非用户明确需要，不展示个人信息或敏感字段。
- 大结果集只做摘要。
- 不展示密码、token、cookie 或完整 DSN。
- 权限不足时，建议使用具备目标 schema/table 读取权限的只读账号。
