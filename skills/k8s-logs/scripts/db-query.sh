#!/usr/bin/env bash
# db-query.sh <env> <service> <SQL> [--database <name>] [--write] [--dry-run]
# 作用: 按配置在 guozhi 各环境查微服务的 MySQL. 通过 kubectl exec 进 db pod 用其内置 mysql 客户端.
# 配置: ~/.zcode/guozhi/config.json 的 db 节点, 结构「环境默认 + 服务覆写」, 详见 references/db.md.
# 安全: 默认只读白名单(SELECT/SHOW/DESC/EXPLAIN)且单条语句; --write 为显式逃逸口(须先获用户同意).
# 退出码: 0 成功 / 2 用法错误 / 3 配置缺失(需引导用户配置) / 4 连接或通道失败 / 5 SQL 被只读白名单拒绝
# 结果走 stdout, 诊断走 stderr(与 resolve-pod.sh 同约定).
set -uo pipefail

CONFIG_PATH="${GUOZHI_CONFIG:-$HOME/.zcode/guozhi/config.json}"

usage() {
  echo "usage: db-query.sh <env> <service> <SQL> [--database <name>] [--write] [--dry-run]" >&2
  echo "  env: dev1|dev2|dev3|fat1|uat; service: 如 guozhi-common-platform" >&2
  exit 2
}

[ $# -lt 3 ] && usage
env="$(echo "$1" | tr 'A-Z' 'a-z')"
svc="$2"
sql="$3"
shift 3

db_override=""
allow_write=0
dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --database) db_override="${2:-}"; [ -n "$db_override" ] || usage; shift 2 ;;
    --write) allow_write=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    *) echo "未知参数: $1" >&2; usage ;;
  esac
done

# ---- 1. 只读白名单(先于一切网络动作, 便宜且安全) ----
first_word="$(printf '%s' "$sql" | awk '{print toupper($1)}')"
case "$first_word" in
  SELECT|SHOW|DESC|DESCRIBE|EXPLAIN) ;;
  *)
    if [ "$allow_write" -eq 1 ]; then
      echo "⚠ --write 逃逸口已启用: 即将执行写操作 SQL, 执行前必须已在对话中获得用户明确同意" >&2
    else
      echo "✗ 拒绝执行非只读 SQL (开头: $first_word)。本 skill 默认只读; 确需写入(如造测试数据), 先向用户确认后加 --write 重试" >&2
      exit 5
    fi ;;
esac
# 单条语句限制: 防止 "SELECT 1; DROP TABLE x" 借白名单首词混入
stmt="$(printf '%s' "$sql" | sed -e 's/[[:space:]]*$//' -e 's/;$//')"
if printf '%s' "$stmt" | grep -q ';'; then
  echo "✗ 拒绝执行: 只支持单条语句(SQL 中含 ';')" >&2
  exit 5
fi

# ---- 2. 读配置并合并「环境默认 + 服务覆写」 ----
if [ ! -f "$CONFIG_PATH" ]; then
  echo "✗ 配置文件不存在: $CONFIG_PATH" >&2
  echo "  → 首次使用需配置: 按 references/db.md 的首次配置流程, 向用户收集凭据写入后再查" >&2
  exit 3
fi
merged="$(jq -r --arg env "$env" --arg svc "$svc" '
  .db[$env] as $e
  | if $e == null then "ENV_MISSING"
    elif ($e[$svc] == null and $e["_default"] == null) then "SVC_MISSING"
    else (($e["_default"] // {}) + ($e[$svc] // {})) | [(.host//""), (.port//""), (.user//""), (.password//""), (.database//"")] | @tsv
    end
' "$CONFIG_PATH" 2>&1)"
case "$merged" in
  ENV_MISSING)
    echo "✗ 配置缺失: config.json 的 db 节点中没有环境 [$env]" >&2
    echo "  → 按 references/db.md 首次配置流程: 向用户收集该环境 host/port/user/password 写入" >&2
    exit 3 ;;
  SVC_MISSING)
    echo "✗ 配置缺失: 环境 [$env] 存在, 但没有服务 [$svc] 也没有 _default" >&2
    echo "  → 至少要有 _default(环境级连接)或该服务自己的完整条目" >&2
    exit 3 ;;
esac
IFS=$'\t' read -r host port user password database <<<"$merged"
[ -n "$db_override" ] && database="$db_override"
[ -n "$host" ] && [ -n "$user" ] || { echo "✗ 配置不完整: [$env/$svc] 缺 host 或 user" >&2; exit 3; }
if [ -z "$database" ]; then
  echo "✗ 配置缺失: [$env/$svc] 未配置 database 名" >&2
  echo "  → 可先用环境 _default 凭据执行 SHOW DATABASES 探测候选库名, 与用户确认后写入配置" >&2
  exit 3
fi

# ---- 3. 解析通道: 目标环境的 db pod; 没有则借道 dev1 跨环境 ----
find_db_pod() { # $1=ns, 输出第一个 Running 且名字含 mysql 的 pod
  kubectl get pods -n "$1" --no-headers 2>/dev/null | awk '$3=="Running" && $1 ~ /mysql/ {print $1; exit}'
}
exec_ns="guozhi-$env"
exec_pod="$(find_db_pod "$exec_ns")"
if [ -n "$exec_pod" ]; then
  hop=""
else
  exec_ns="guozhi-dev1"
  exec_pod="$(find_db_pod "$exec_ns")"
  hop="借道"
fi
if [ -z "$exec_pod" ]; then
  echo "✗ 通道失败: guozhi-$env 无 db pod 且 dev1 也找不到可用 db pod, 检查集群连通性" >&2
  exit 4
fi
[ -n "$hop" ] && echo "⚠ guozhi-$env 集群内无 db pod(库在集群外), 借道 $exec_ns/$exec_pod 跨环境连接; 若网络不通需用户提供查询入口" >&2

db_args=()
[ -n "$database" ] && db_args=("$database")

# ---- 4. dry-run 或执行 ----
if [ "$dry_run" -eq 1 ]; then
  echo "[dry-run] env=$env svc=$svc"
  echo "[dry-run] exec: kubectl exec -n $exec_ns $exec_pod -c mysql -- env MYSQL_PWD=*** mysql -h $host -P $port -u $user ${database}"
  echo "[dry-run] sql: $sql"
  exit 0
fi

# 密码经容器内环境变量传递, 不进命令行(ps 不可见); 命令在 -- 之后按 argv 直传, 不经远端 shell, 无二次引号问题
err_file="$(mktemp)"
kubectl exec -n "$exec_ns" "$exec_pod" -c mysql -- env MYSQL_PWD="$password" mysql \
  --default-character-set=utf8mb4 -h "$host" -P "$port" -u "$user" "${db_args[@]}" -e "$sql" 2>"$err_file"
rc=$?
if [ $rc -ne 0 ]; then
  cat "$err_file" >&2
  grep -q '1045' "$err_file" && echo "→ Access denied: 检查配置里 user/password" >&2
  grep -q '1049' "$err_file" && echo "→ Unknown database: 检查 database 名(可用 SHOW DATABASES 探测)" >&2
  grep -qE '2003|2005' "$err_file" && echo "→ 连不上 host:port: 检查配置或网络(fat1/uat 集群外库可能不可达)" >&2
  rm -f "$err_file"
  exit 4
fi
rm -f "$err_file"
