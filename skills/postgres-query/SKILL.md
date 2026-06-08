---
name: postgres-query
description: 引导式 PostgreSQL/pgsql/PG 数据库连接、本机多 profile 配置、临时连接信息收集、只读查询、表结构查看和查询计划分析。Use when the user asks to query PostgreSQL data, inspect schemas/tables/indexes, run SELECT/WITH/SHOW/EXPLAIN SQL, diagnose slow PostgreSQL queries, configure reusable local database profiles, or needs guided database connection setup. 连接方式不明确时必须先询问临时连接信息；风险写入或 DDL 请求只生成 SQL，不直接执行。
---

# PostgreSQL Query

## 触发规则

遇到 PostgreSQL、pgsql、PG、数据库查询、表结构、字段、索引、`SELECT`、`WITH`、`SHOW`、`EXPLAIN`、慢 SQL 分析等请求时，先使用这个 skill。

典型场景：
- 查询 PostgreSQL 表里的数据。
- 查看 schema、表、字段、主键、外键、索引。
- 执行只读 SQL 并整理结果。
- 分析 PostgreSQL 查询计划或慢 SQL。
- 用户说“连接数据库查一下”“查 pgsql 数据”“看一下 PG 表结构”。

## 执行入口

优先使用脚本，所有脚本输出 JSON。Agent 应读取 JSON 的 `ok`、`error`、`message`、`next_action`、`install_commands`、`rows`、`findings` 字段决定下一步。

- 只读查询：`python scripts/pg_query.py --sql "select now()" --limit 20`
- 结构查看：`python scripts/pg_schema.py --list-tables --schema public`
- 表详情：`python scripts/pg_schema.py --table public.orders`
- 查询计划：`python scripts/pg_explain.py --sql "select * from public.orders where id = 123"`
- 查看本地连接别名：`python scripts/pg_profiles.py`

连接信息可以用临时 DSN：

```bash
python scripts/pg_query.py --dsn "postgresql://user:password@host:5432/db" --sql "select now()"
```

也可以用环境变量：

```text
POSTGRES_DSN
PGHOST
PGPORT
PGDATABASE
PGUSER
PGPASSWORD
PGSSLMODE
```

也可以用本机连接配置：

```bash
python scripts/pg_query.py --profile example-readonly-db --sql "select now()"
```

本机配置文件位置：

```text
skills/postgres-query/scripts/connections.local.json
```

`connections.local.json` 直接内置示例数据，可以配置多个 `profiles`；密码优先使用 `passwordEnv` 指向环境变量，避免把明文密码写入仓库。

## 标准流程

1. 判断是否真的需要连接 PostgreSQL。
   - 如果能从本地代码、配置或文档回答，先用本地上下文，不主动连接数据库。
   - 如果用户明确要查库、看表结构、执行 SQL 或分析查询计划，进入连接流程。
2. 查找连接配置。
   - 优先使用用户本轮明确提供的临时 DSN 或连接参数。
   - 其次使用用户明确指定的 `--profile <连接别名>`。
   - 再使用 `POSTGRES_DSN` 或完整的 `PGHOST/PGDATABASE/PGUSER` 等环境变量。
   - 最后才使用 `connections.local.json` 的 `defaultProfile`。
   - 只有当用户明确要求使用当前项目连接时，才检查 `.env`、`.env.local`、`.env.development` 或项目文档中的连接配置；不得打印密码。
3. 连接方式不明确时，必须先询问用户。
   - 询问临时 DSN，或 host、port、database、username、password、sslmode。
   - 提醒用户优先提供只读账号。
   - 提醒用户不要提供非预期环境的生产库凭据。
   - 不把连接信息写入仓库、引用文档或最终回答；如需长期复用，只能写入使用者本机安装目录的 `connections.local.json`，且优先用 `passwordEnv` 保存密码。
4. 检查本机 PostgreSQL Python 驱动。
   - 脚本优先使用 `psycopg`，其次使用 `psycopg2`。
   - 如果返回 `error: missing_driver`，读取 `references/driver_install.md`，用中文引导用户安装。
   - 安装依赖前必须先征得用户确认；不要擅自联网安装。
5. 分类 SQL 风险。
   - 默认允许：`SELECT`、只读 `WITH`、`SHOW`、元数据查询、无 `ANALYZE` 的 `EXPLAIN`。
   - 默认禁止执行：`INSERT`、`UPDATE`、`DELETE`、`TRUNCATE`、`DROP`、`ALTER`、`CREATE`、`GRANT`、`REVOKE`、`VACUUM`、`CALL`、`DO`、`COPY`、`MERGE`、`REFRESH MATERIALIZED VIEW`、`EXPLAIN ANALYZE`、包含写入的事务。
6. 只执行只读操作。
   - 用 `scripts/pg_query.py` 执行只读查询。
   - 用 `scripts/pg_schema.py` 查看库表结构。
   - 用 `scripts/pg_explain.py` 查看查询计划。
   - 查询样例数据时默认限制行数，避免无意义输出大结果集。
7. 风险操作只生成 SQL。
   - 不直接执行风险 SQL。
   - 输出 SQL、影响范围、执行前检查、执行后验证、回滚思路。
   - 明确告诉用户在已授权的数据库工具或发布流程中自行执行。
8. 输出结果时保护敏感信息。
   - 只报告使用了哪类连接来源，例如 `POSTGRES_DSN` 或 `PGHOST/PGDATABASE`。
   - 不展示完整 DSN、密码、token、cookie。
   - 大结果集只做摘要。
   - 个人信息或敏感字段只在用户明确需要时展示必要部分。

## 引导话术

连接信息不明确时，使用类似话术：

```text
我需要临时的 PostgreSQL 连接信息才能查询。请提供以下任一方式：
1. 临时 DSN：postgresql://user:password@host:5432/dbname
2. 分项信息：host、port、database、username、password、sslmode（如需要）

建议使用只读账号；如果是生产库，请确认你确实希望查询该环境。我不会把连接信息写入 skill 或最终结果。
```

缺少 Python 驱动时，使用类似话术：

```text
本机缺少 PostgreSQL Python 驱动，脚本需要安装 `psycopg` 或 `psycopg2` 才能连接数据库。
推荐安装：python -m pip install "psycopg[binary]"
备选安装：python -m pip install psycopg2-binary

是否允许我为当前 Python 环境安装推荐驱动？
```

风险操作时，使用类似话术：

```text
这个请求会修改数据库。我不会直接执行。下面是可由你在授权工具中执行的 SQL：

[SQL]

影响范围：...
执行前检查：...
执行后验证：...
回滚思路：...
```

## 规则导航

按需读取这些 reference，不要默认整篇加载：

- 连接配置和临时凭据：`references/connection.md`
- 驱动缺失和安装引导：`references/driver_install.md`
- 只读边界和风险 SQL：`references/safety.md`
- 常见元数据 SQL：`references/common_queries.md`

## 错误处理

- `missing_connection`：向用户索取临时 DSN 或 host/port/database/user/password。
- `config_missing`：提示用户在 `scripts/connections.local.json` 中配置 `profiles`。
- `profile_not_found`：运行 `python scripts/pg_profiles.py` 或检查 `connections.local.json` 的 `profiles`。
- `password_env_missing`：提示用户设置 profile 中 `passwordEnv` 指向的环境变量。
- `missing_driver`：读取 `references/driver_install.md`，引导安装 `psycopg[binary]`，安装前等待确认。
- `connection_failed`：说明连接失败类型，隐藏密码和完整 DSN。
- 权限不足：建议使用有目标 schema/table 读取权限的只读账号。
- SQL 错误：简要引用数据库错误，给出修正方向。
- 超时：建议缩小筛选条件、查看索引或先跑 `EXPLAIN`。

## 最终反馈

完成后只报告：
- 使用的连接来源，必须脱敏。
- 操作类型：只读查询、结构查看、查询计划、或仅生成 SQL。
- 结果摘要、关键行或关键发现。
- 未完成原因、需要的连接信息、或是否需要用户确认安装驱动。
