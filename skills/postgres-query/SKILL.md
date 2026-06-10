---
name: postgres-query
description: 引导式 PostgreSQL/pgsql/PG 数据库连接、本机多 profile 配置、临时连接信息收集、只读查询、表结构查看和查询计划分析。Use when the user asks to query PostgreSQL data, inspect schemas/tables/indexes, run SELECT/WITH/SHOW/EXPLAIN SQL, diagnose slow PostgreSQL queries, configure reusable local database profiles, or needs guided database connection setup. 连接方式不明确时必须先询问临时连接信息；风险写入或 DDL 请求只生成 SQL，不直接执行。
---

# PostgreSQL Query

## 围栏（代码强制，不可绕过）

以下限制由脚本代码执行，AI 无法选择是否遵守：

- **只读白名单**：`sql_guard.py` 只放行 `SELECT`、`WITH`、`SHOW`、`EXPLAIN`（不含 ANALYZE）。其他一律 `raise ValueError`。
- **危险关键字拦截**：SQL 经过字面值/注释遮蔽后，出现 INSERT/UPDATE/DELETE/DROP/ALTER/CREATE/TRUNCATE/GRANT/REVOKE/VACUUM/CALL/DO/COPY/MERGE/REFRESH/LOCK/SETVAL/NEXTVAL 即拒绝。
- **硬上限**：单次最多 1000 行（`MAX_ROWS`），超时最长 120 秒（`MAX_TIMEOUT`）。
- **凭据脱敏**：`redact()` 在所有输出路径上遮蔽密码。
- **审计留痕**：每次查询、拦截、连接事件写入 `scripts/audit.local.jsonl`。
- **无连接不执行**：连接信息缺失时脚本输出错误并停止，不猜测。

## 脚本入口

```bash
python scripts/pg_query.py   --sql "..." [--limit N] [--dsn|--profile]
python scripts/pg_schema.py  --sql "..." | --list-schemas | --list-tables | --table schema.table
python scripts/pg_explain.py --sql "..."
python scripts/pg_profiles.py
```

连接优先级：`--dsn` > `--profile` > `POSTGRES_DSN` > `PGHOST/...` 环境变量 > `connections.local.json`。

详见 `references/connection.md`。

## 围栏以内（AI 自由发挥）

在上述围栏的保护下，AI 自行决定：

- 写什么 SQL
- 怎么跟用户沟通
- 怎么解释结果
- 是否需要多次查询
- 如何引导用户提供连接信息
- 如何处理错误和重试
