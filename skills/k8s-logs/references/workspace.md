# Workspace 配置权威参考（跨微服务定位本地仓库）

> SKILL.md 的「跨服务查代码」节是入口；本篇是配置 schema、首次配置与随时调整流程、匹配规则的完整版。
> 与 db 凭据共用同一个配置文件 `~/.zcode/guozhi/config.json`——db 部分见 `references/db.md`，两节互不干扰。

## 为什么需要它

排查常要跨微服务看代码：traceId 追到下游服务、看某个 entity 的字段定义（db 表结构反推也靠它）、对照接口实现。服务仓库散在用户自己的工作区里，路径因人而异——所以做成配置，而不是写死 `D:/workspace`。

## 配置 schema

`~/.zcode/guozhi/config.json` 顶层的 `_workspace` 节点（与 `db` 节点平级）：

```json
{
  "_workspace": {
    "roots": ["D:/workspace", "D:/work-other"],
    "repos": {
      "guozhi-legacy-pay": "D:/old-checkouts/legacy-pay"
    }
  }
}
```

- `roots`：扫描根目录数组。按 guozhi 惯例，`<root>/guozhi-<服务名>/` 即服务仓库，绝大多数仓库靠 roots 自动命中，不用逐个登记。
- `repos`：例外显式映射，键为服务名（带不带 `guozhi-` 前缀都行）。用于目录名不按约定、或仓库 clone 在 roots 之外的情况。**优先级最高**，命中即返回，不再扫描。

注意：这个文件同时存着 db 密码，**绝不写进任何 git 仓库、文档或对话外产物**；展示配置时密码打码。

## 首次配置流程（agent 执行）

触发时机：`resolve-repo.sh` 退出码 3 且 stderr 提示未配置。

1. 问用户一句：「guozhi 的仓库都 clone 在哪个目录？」（通常一个根目录就够，如 `D:/workspace`）。
2. 用 `ls <根目录> | grep -i guozhi-` 确认根目录下确实有一批 guozhi-* 仓库，再写入 `_workspace.roots`。
3. 验证：挑一个用户最近提到的服务跑 `resolve-repo.sh <服务名>`，唯一命中即配置完成，告知用户已保存、以后不用再配。

## 随时调整流程

配置不是一次性的，用户随时说以下这类话就直接改 `~/.zcode/guozhi/config.json`，改完立即生效、无需重启：

- 「我仓库挪到 X 了」→ 改 `roots`；
- 「新 clone 了某服务 / 某服务目录名不对」→ 若 roots 扫不到，往 `repos` 加一条显式映射；
- 「repos 里那条路径过期了」→ 更新或删掉该条。

改完用受影响的服务跑一次 `resolve-repo.sh` 验证，并向用户确认。

## resolve-repo.sh 用法与语义

```bash
bash <本skill目录>/scripts/resolve-repo.sh <服务名或关键字>
```

- 结果走 stdout（就一行：仓库绝对路径，正斜杠），诊断与候选列表走 stderr（与 resolve-pod.sh 同约定）。
- 退出码：`0` 成功 / `2` 用法错误 / `3` 未配置或未找到 / `6` 多候选歧义。
- 匹配顺序：
  1. `repos` 显式映射（服务名与 `guozhi-` 前缀两种键都试）；
  2. 各 root 下精确目录 `guozhi-<服务名>`；
  3. 关键字对 root 下一级目录名做大小写不敏感的模糊匹配——**唯一命中自动选定；命中多个时退出码 6，stderr 列出全部候选**，此时把候选列给用户选，或根据上下文用更精确的名字重试。
- 退出码 3 的两种情况（配置缺失 / 找不到）在 stderr 里措辞不同，按提示走对应流程。

## 典型场景

- **traceId 跨服务追代码**：日志显示异常来自下游服务 → `resolve-repo.sh <下游服务>` → 在该仓库 grep 关键字。
- **entity 反推表结构**：db 查询前先 `resolve-repo.sh <服务>` 拿仓库路径，再 `grep -rl '@TableName("...")'`，完整规则见 `references/db.md`。
- **确认某接口/类在哪个服务**：多候选歧义（退出码 6）时逐个仓库 grep 比对。
