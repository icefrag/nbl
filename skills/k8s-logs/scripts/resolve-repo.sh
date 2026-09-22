#!/usr/bin/env bash
# resolve-repo.sh <服务名或关键字>
# 作用: 把服务名解析成本地 git 仓库路径, 供跨微服务查代码 / entity 反推表结构使用.
# 配置: ~/.zcode/guozhi/config.json 的 _workspace 节点(roots=扫描根目录数组, repos=例外显式映射), 详见 references/workspace.md.
# 匹配顺序: repos 显式映射 → 各 root 下 guozhi-<服务名> 精确目录 → 关键字模糊(唯一命中自动选定, 多候选退出码 6).
# 退出码: 0 成功 / 2 用法错误 / 3 未配置或未找到 / 6 多候选歧义
# 仓库路径走 stdout, 诊断与候选列表走 stderr(与 resolve-pod.sh 同约定).
set -uo pipefail

CONFIG_PATH="${GUOZHI_CONFIG:-$HOME/.zcode/guozhi/config.json}"

[ $# -eq 1 ] || { echo "usage: resolve-repo.sh <服务名或关键字>" >&2; exit 2; }
svc="$1"

if [ ! -f "$CONFIG_PATH" ]; then
  echo "✗ 配置文件不存在: $CONFIG_PATH" >&2
  echo "  → 首次使用需配置: 问用户 guozhi 仓库都放在哪个根目录, 写入 _workspace.roots; 详见 references/workspace.md" >&2
  exit 3
fi

# repos 显式映射优先(服务名与 guozhi- 前缀两种键都试)
name="$svc"; case "$name" in guozhi-*) ;; *) name="guozhi-$name" ;; esac
repo="$(jq -r --arg svc "$svc" --arg name "$name" \
  '._workspace.repos[$svc] // ._workspace.repos[$name] // ""' "$CONFIG_PATH")"
if [ -n "$repo" ]; then
  if [ -d "$repo" ]; then
    printf '%s\n' "$repo"
    exit 0
  fi
  echo "✗ repos 里配置的路径不存在: $repo (修正 _workspace.repos)" >&2
  exit 3
fi

roots="$(jq -r '._workspace.roots // [] | .[]' "$CONFIG_PATH")"
if [ -z "$roots" ]; then
  echo "✗ 未配置 workspace: config.json 缺 _workspace.roots" >&2
  echo "  → 问用户 guozhi 仓库放在哪个根目录(如 D:/workspace), 写入后重试; 详见 references/workspace.md" >&2
  exit 3
fi

# 先按约定目录名精确找, 全空再关键字模糊
hits=()
while IFS= read -r root; do
  [ -d "$root/$name" ] && hits+=("$root/$name")
done <<< "$roots"
if [ ${#hits[@]} -eq 0 ]; then
  while IFS= read -r root; do
    while IFS= read -r d; do hits+=("$root/$d"); done < <(ls -1 "$root" 2>/dev/null | grep -iF "$svc")
  done <<< "$roots"
fi

case ${#hits[@]} in
  0)
    echo "✗ 在 _workspace.roots 里找不到 [$svc] (试过精确 $name 与关键字模糊)" >&2
    echo "  → 若目录名不按 guozhi-<服务名> 约定、或仓库放在别的位置, 把实际路径写进 _workspace.repos" >&2
    exit 3 ;;
  1)
    printf '%s\n' "${hits[0]}"
    exit 0 ;;
  *)
    echo "✗ 关键字 [$svc] 命中多个仓库, 请用户选择或改用更精确的名字:" >&2
    for h in "${hits[@]}"; do echo "  - $h" >&2; done
    exit 6 ;;
esac
