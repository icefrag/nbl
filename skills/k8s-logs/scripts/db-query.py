#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""guozhi 各环境 MySQL 查询工具（本地直连通道）。

背景：查询账号有来源 IP 白名单，放行开发机、不放行 K8s 集群 pod，
kubectl exec 借道 db pod 的通道已不可用，必须本地直连。

调用（零安装，uv 临时解析依赖）:
    uv run --no-project --with pymysql --with cryptography python <本脚本> <env> <service> <SQL> [--database X] [--write] [--dry-run]

配置:
    ~/.zcode/guozhi/config.json 的 db 节点，「环境 _default + 服务覆写」，
    服务条目可覆写任意字段（host/port/user/password/database）。

退出码: 0 成功 / 2 用法错误 / 3 配置缺失 / 4 连接失败 / 5 SQL 被白名单拒绝
"""
import argparse
import json
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

CONFIG_PATH = Path.home() / ".zcode" / "guozhi" / "config.json"
READ_ONLY_PREFIXES = ("SELECT", "SHOW", "DESC", "DESCRIBE", "EXPLAIN")


def load_db_config(env: str, service: str, database_override):
    if not CONFIG_PATH.exists():
        print(f"配置文件不存在: {CONFIG_PATH}", file=sys.stderr)
        sys.exit(3)
    cfg = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    env_cfg = cfg.get("db", {}).get(env)
    if not isinstance(env_cfg, dict) or "_default" not in env_cfg:
        print(f"环境 {env} 未配置 _default", file=sys.stderr)
        sys.exit(3)
    merged = dict(env_cfg["_default"])
    svc_cfg = env_cfg.get(service)
    if isinstance(svc_cfg, dict):
        merged.update(svc_cfg)
    for field in ("host", "port", "user", "password"):
        if field not in merged:
            print(f"环境 {env} 服务 {service} 配置缺少 {field}", file=sys.stderr)
            sys.exit(3)
    database = database_override or merged.get("database")
    if not database:
        print(f"环境 {env} 服务 {service} 未配置 database，可先 --database information_schema 探测", file=sys.stderr)
        sys.exit(3)
    return merged["host"], int(merged["port"]), merged["user"], merged["password"], database


def check_sql(sql: str, allow_write: bool) -> None:
    single = sql.strip().rstrip(";").strip()
    if not single:
        print("SQL 为空", file=sys.stderr)
        sys.exit(2)
    if ";" in single:
        print("拒绝：只允许单条语句", file=sys.stderr)
        sys.exit(5)
    first = single.split(None, 1)[0].upper()
    if not allow_write and first not in READ_ONLY_PREFIXES:
        print(f"拒绝：只读模式仅放行 {'/'.join(READ_ONLY_PREFIXES)}；写操作需用户明确同意后加 --write", file=sys.stderr)
        sys.exit(5)


def main():
    parser = argparse.ArgumentParser(description="guozhi 环境 MySQL 查询（本地直连）")
    parser.add_argument("env")
    parser.add_argument("service")
    parser.add_argument("sql")
    parser.add_argument("--database")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    host, port, user, password, database = load_db_config(args.env, args.service, args.database)
    check_sql(args.sql, args.write)
    if args.dry_run:
        print(f"channel=local-direct env={args.env} host={host}:{port} user={user} db={database}")
        print(f"sql={args.sql}")
        return

    import pymysql

    try:
        conn = pymysql.connect(
            host=host, port=port, user=user, password=password,
            database=database, charset="utf8mb4", connect_timeout=10,
        )
    except pymysql.err.OperationalError as e:
        print(f"连接失败: {e}", file=sys.stderr)
        sys.exit(4)

    try:
        with conn.cursor() as cur:
            cur.execute(args.sql)
            if cur.description:
                print("\t".join(d[0] for d in cur.description))
                for row in cur.fetchall():
                    print("\t".join("NULL" if v is None else str(v) for v in row))
            else:
                conn.commit()
                print(f"OK, rowcount={cur.rowcount}")
    except pymysql.err.Error as e:
        print(f"SQL 执行失败: {e}", file=sys.stderr)
        sys.exit(4)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
