# PostgreSQL 常用元数据查询

用于 schema 发现和诊断。能用脚本时优先使用 `scripts/pg_schema.py`。

## 当前会话

```sql
select current_database(), current_user, now();
```

## 查看 schema

```sql
select schema_name
from information_schema.schemata
where schema_name not like 'pg_%'
  and schema_name <> 'information_schema'
order by schema_name;
```

## 查看某个 schema 下的表

```sql
select table_schema, table_name, table_type
from information_schema.tables
where table_schema = 'public'
order by table_name;
```

## 查看字段

```sql
select column_name, data_type, is_nullable, column_default, ordinal_position
from information_schema.columns
where table_schema = 'public'
  and table_name = 'your_table'
order by ordinal_position;
```

## 查看索引

```sql
select schemaname, tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'your_table'
order by indexname;
```

## 查看约束

```sql
select tc.constraint_type,
       kcu.column_name,
       ccu.table_schema as foreign_table_schema,
       ccu.table_name as foreign_table_name,
       ccu.column_name as foreign_column_name
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on tc.constraint_name = kcu.constraint_name
 and tc.table_schema = kcu.table_schema
left join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = tc.constraint_name
 and ccu.table_schema = tc.table_schema
where tc.table_schema = 'public'
  and tc.table_name = 'your_table'
order by tc.constraint_type, kcu.ordinal_position;
```

## 估算行数

```sql
select n.nspname as schema_name,
       c.relname as table_name,
       c.reltuples::bigint as estimated_rows
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'your_table';
```

## 安全查询计划

```sql
explain
select *
from public.your_table
where id = 123;
```

默认不要使用 `EXPLAIN ANALYZE`，因为它会实际执行查询。
