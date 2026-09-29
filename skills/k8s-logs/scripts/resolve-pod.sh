#!/usr/bin/env bash
# resolve-pod.sh <namespace> <服务关键字>
# 作用: 在指定 namespace 下按服务关键字模糊匹配 pod, 返回一个稳定(已 Running)的 pod.
# 约定: 若该服务存在多个副本, 视为"正在滚动发布", 在 stderr 告警(用户明确要求此语义).
# 输出: 选中 pod 名 -> stdout; 诊断/告警 -> stderr.
set -uo pipefail

ns="${1:-}"
svc="${2:-}"
if [ -z "$ns" ] || [ -z "$svc" ]; then
  echo "usage: resolve-pod.sh <namespace> <服务关键字>" >&2
  exit 2
fi

# KUBECONFIG 默认导出(环境未设时): 本 skill 的环境(dev1~uat)全在测试系 kubeconfig.
# Git Bash 下必须用 C:/ 正斜杠 Windows 路径, ~ 或 /c/ 均读不到.
export KUBECONFIG="${KUBECONFIG:-C:/Users/$USERNAME/.kube/guozhi-test-config}"

# 连通性预检: kubectl 连不上集群时, 错误不能被下面的 2>/dev/null 吞掉后伪装成"未找到 pod"
if ! kubectl get pods -n "$ns" --no-headers >/dev/null 2>&1; then
  echo "kubectl 连不上集群——大概率 KUBECONFIG 未导出/指错。先执行: export KUBECONFIG=\"C:/Users/$USERNAME/.kube/guozhi-test-config\" (Git Bash 必须用 C:/ 正斜杠路径)" >&2
  exit 4
fi

# 取该 namespace 下所有 pod (NAME READY STATUS RESTARTS AGE), 模糊匹配服务名
mapfile -t lines < <(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -i "$svc")
if [ ${#lines[@]} -eq 0 ]; then
  echo "在 $ns 下未找到匹配 '$svc' 的 pod。可用 pod:" >&2
  kubectl get pods -n "$ns" -o name 2>/dev/null | head -40 >&2
  exit 1
fi

# 解析每个 pod 的名字与状态
pods=()           # "name|status"
declare -A grp    # deploy前缀 -> 副本数
for line in "${lines[@]}"; do
  name="$(awk '{print $1}' <<<"$line")"
  status="$(awk '{print $3}' <<<"$line")"
  pods+=("$name|$status")
  # deploy 前缀 = pod 名去掉最后两段(-<rs-hash>-<pod-hash>)
  prefix="$(awk -F- '{NF--; NF--; print}' OFS=- <<<"$name")"
  grp["$prefix"]=$(( ${grp["$prefix"]:-0} + 1 ))
done

# 优先选已 Running 的 pod (滚动发布时旧副本通常先 Ready)
chosen=""
for p in "${pods[@]}"; do
  if [ "${p#*|}" = "Running" ]; then chosen="${p%|*}"; break; fi
done
[ -z "$chosen" ] && chosen="${pods[0]%|*}"  # 兜底取第一个

# 多副本告警(滚动发布语义)
multi=""
for prefix in "${!grp[@]}"; do
  if [ "${grp[$prefix]}" -gt 1 ]; then
    multi="${multi} ${prefix}(${grp[$prefix]}副本)"
  fi
done
if [ -n "$multi" ]; then
  echo "⚠ 检测到多副本(疑似滚动发布中):${multi}。已选 $chosen；若日志不全，建议稍后发布稳定再查。" >&2
fi

echo "$chosen"
