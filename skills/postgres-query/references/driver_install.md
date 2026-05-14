# PostgreSQL 驱动安装引导

当脚本返回 `error: missing_driver` 时读取本文件。

## 判断

`scripts/pg_query.py`、`scripts/pg_schema.py`、`scripts/pg_explain.py` 需要 Python PostgreSQL 驱动。脚本会按顺序尝试：

1. `psycopg`
2. `psycopg2`

两个都不存在时，返回 `missing_driver`。

## 用户引导

先说明原因，再请求确认：

```text
本机缺少 PostgreSQL Python 驱动，脚本需要安装 `psycopg` 或 `psycopg2` 才能连接数据库。
推荐安装：python -m pip install "psycopg[binary]"
备选安装：python -m pip install psycopg2-binary

是否允许我为当前 Python 环境安装推荐驱动？
```

## 安装命令

推荐：

```powershell
python -m pip install "psycopg[binary]"
```

备选：

```powershell
python -m pip install psycopg2-binary
```

如果项目使用虚拟环境，先提示用户确认当前 shell 是否已激活虚拟环境。不要擅自安装到全局 Python 环境。

## 安装后验证

安装完成后运行：

```powershell
python -c "import psycopg; print('psycopg ok')"
```

如果安装的是 `psycopg2-binary`，运行：

```powershell
python -c "import psycopg2; print('psycopg2 ok')"
```

验证通过后再继续数据库连接流程。

## 失败处理

- 网络失败：说明 pip 无法访问包源，询问是否使用代理或公司镜像源。
- 权限失败：建议使用虚拟环境或用户级安装。
- Python 版本不兼容：报告当前 Python 版本，并建议使用项目要求的 Python 环境。
- 公司环境禁止联网安装：建议用户在内部制品库安装驱动，或使用 `psql` 按只读规则手动执行。
