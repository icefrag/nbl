---
name: k8s-logs
description: 排查 guozhi 项目在 K8s 各环境(dev1/dev2/dev3/fat1/uat)服务日志与数据库的专属技能。当用户提到查日志/看日志/app.log/error.log/warn.log/request.log、服务报错/接口失败/超时/500/空指针、某环境(dev1~uat)某服务(guozhi-*)出问题、kexi/kubectl 进 pod 看日志、启动失败/Bean 报错/性能慢/耗时高/Full GC/内存溢出等任何线上/测试环境排查诉求时，必须使用本 skill；当用户要查库/查数据/看表结构/字段含义/核对数据是否落库/分析 SQL 报错时也必须使用本 skill——通过本地直连（pymysql，账号白名单放行开发机、封禁集群 pod）执行只读 SQL，凭据按环境+服务存于本地配置，表结构从代码 entity 反推；当用户要跨微服务查代码/找某服务的本地仓库/改 db 或 workspace 配置时也必须使用本 skill。本 skill 通过 kubectl 直接操作集群抓取日志与查询数据、给出结论，用户无需再手动与 kexi 交互。
---

# K8s 日志排查（guozhi）

## 这个 skill 的本质

用户本地有个 `kexi` 交互命令（在 PowerShell profile 里），本质是 `kubectl exec -it <pod> -n <ns> -- sh` 的菜单式封装——那个「选环境→选服务」的菜单只是辅助选 namespace 和 pod 名。

**你不需要、也不应该去模拟那个交互式菜单（驱动 TTY 交互极脆弱）。** Claude Code 的 Bash 工具能直接调 `kubectl`（kubeconfig 已就绪、context 指向目标 ACK 集群），把 namespace 和 pod 当参数传进去，一条非交互命令就能把日志捞出来。

所以你的角色：用户用自然语言描述「哪个环境、哪个服务、什么问题」→ 你翻译成精确的 kubectl 日志查询 → 抓取 → 分析 → 给出结论。

## 工作流

### 1. 解析「环境 + 服务 + 问题」

从用户描述里提取三个要素：

| 要素 | 说明 | guozhi 环境/ns |
|------|------|--------------|
| 环境(ns) | `dev1`/`dev2`/`dev3`/`fat1`/`uat` | 实际 ns = `guozhi-dev1` … `guozhi-uat` |
| 服务 | 用户口中的服务名，可能是简称 | pod 前缀，如 `guozhi-common-platform`、`guozhi-api-main`、`guozhi-gateway` |
| 问题类型 | 报错 / 启动失败 / 性能慢 / 请求异常 / GC… | 决定查哪个日志文件（见下表） |

- 用户通常会带环境（如「dev3 的 common-platform 报错了」）。**若描述里提取不到环境或服务，必须反问，不要猜环境**——查错环境会误导结论。
- 服务名到 pod 前缀的映射：pod 命名为 `<deploy>-<rs-hash>-<pod-hash>`（如 `guozhi-common-platform-7b7ffc4f5b-554h9`），**服务名 = 去掉最后两段 hash**。用户给的可能是 `common-platform`，你用模糊匹配即可。

### 2. 定位 pod（用 helper 脚本）

直接调用本 skill 自带的解析脚本，避免每次手写一堆 grep+判断：

```bash
bash <本skill目录>/scripts/resolve-pod.sh <namespace> <服务关键字>
# 例(本skill目录 = 本 SKILL.md 所在目录):
bash <本skill目录>/scripts/resolve-pod.sh guozhi-dev3 common-platform
```

- 脚本把选中的 pod 名打印到 **stdout**，诊断信息打印到 **stderr**。
- **关键约定（用户明确要求）**：若该服务存在多个副本，说明**服务正在滚动发布中**。脚本会在 stderr 告警 `⚠ 检测到多副本(疑似滚动发布中)`。此时你应当：
  1. 告诉用户「服务正在发布（已有 N 个副本），日志可能不全」；
  2. 优先查已经 `Running` 的那个旧副本（脚本会自动选）；
  3. 若用户不急，建议「等一会儿、发布稳定后再查」。
- 脚本失败（找不到 pod）时，你自己 `kubectl get pods -n <ns> | grep -i <关键字>` 兜底，把候选 pod 列给用户确认。

### 3. 选日志文件（按问题类型智能选）

日志根目录 = `/data/log/<服务名>/`（服务名即 pod 前缀，与 pod 名去 hash 一致）。

| 问题类型 | 首选文件 | 必要时扩散 |
|---------|---------|-----------|
| 报错/异常/500/NPE | `error.log` | `warn.log` |
| 业务流程/逻辑走向 | `app.log`（全量业务日志，最常用） | `info.log` |
| 接口请求/入参/响应 | `app.log`（REQUEST-LOGGER 写这里，非 request.log） | `logstash.log` |
| 按 traceId 串全链路 | `logstash.log`（JSON，字段 `trace`/`span`） | `app.log`(grep traceId) |
| 耗时/性能慢 | `time.log` | `app.log` |
| 内存/Full GC/OOM | `gc.log`（JVM 层，含滚动 `gc.log.0~4`） | `error.log` |
| 启动失败 | `start.log`（JVM 层） | `error.log` |
| 不确定/总览 | `error.log`（grep ERROR）+ `app.log`（tail） | — |

**归档与保留**：所有 logback 文件**按小时滚动**为 `archive/<file>.log.<yyyyMMddHH>.gz`，仅保留 **72 小时**（约 3 天）。3 天前的日志本地没有，只能去 ELK——`logstash.log` 的 JSON 格式就是给 ELK 采集用的。查「昨天/某时段」先 `ls archive/` 看有哪些归档小时，再 grep。

**⚠ request.log 已废弃**：当前 logback 配置里**没有 request appender**，磁盘上残留的 `request.log` 是旧版本遗留、不再写入（实测 mtime 能停在半个月前）。请求日志实际由 `REQUEST-LOGGER` 写入 **app.log + logstash.log**——排查请求别再查 request.log。

**JVM 层日志**（`gc.log`/`gc.log.0~4`/`start.log` 等）由 JVM 启动参数输出，不归 logback 管，文件名/滚动由 JVM 决定。

### 日志格式速记（grep 不抓瞎）

排查时八成要 grep，这几个格式细节决定了你的 grep 能不能命中，先记牢：

- **纯文本文件**（`app/error/warn/info/time.log`）行格式：`[时间] - 级别 - logger - appName - class[line] - traceId - spanId - thread - msg`（` - ` 分隔共 9 段）。**traceId 是第 6 段**，直接 `grep '<traceId>'` 就能串全链路；中文正常显示，可 grep 中文关键字。
- **`logstash.log` 是 JSON**，字段名是 `trace`/`span`/`rest`。按 traceId 用 `grep '"trace":"<id>"'`；但 **`rest` 里的中文被 unicode 转义**（如「请求结束」存成 `请求结束`），所以 **grep 中文关键字在 logstash.log 里打不中**——要 grep 中文，只能用 app/error 等纯文本文件。
- `logLevel=INFO`，**DEBUG/TRACE 默认不输出**，别去找 DEBUG 日志。

> 需要精确判断「某条日志到底去了哪个文件」（比如某个 logger 写哪、第三方库 INFO 在哪）时，读 `references/logback-routing.md`——里面有完整的 logger→appender 路由表。

### 4. 抓日志（命令模板）

**核心原则：非交互。绝不要带 `-it`，绝不要 `tail -f`（不会结束）。** 用 `kubectl exec ... -- sh -c "..."` 把命令一次性传进去。

抓之前先想清楚量——`app.log`/`info.log` 可能很大，**绝不能 cat 全量**。先统计命中规模再决定抓多少：

```bash
POD=<脚本返回的 pod>; NS=<ns>; SVC=<服务名>; DIR=/data/log/$SVC

# 1) 先看命中规模（便宜，先跑）
kubectl exec -n $NS $POD -- sh -c "grep -c 'ERROR' $DIR/error.log"

# 2) 抓尾部最新
kubectl exec -n $NS $POD -- sh -c "tail -n 300 $DIR/error.log"

# 3) grep 关键字 + 后文上下文（异常栈通常在报错行之后）
kubectl exec -n $NS $POD -- sh -c "grep -n -A 30 'NullPointerException' $DIR/error.log"

# 4) 多关键字 OR / 大小写不敏感
kubectl exec -n $NS $POD -- sh -c "grep -E -i 'timeout|refused' $DIR/error.log"

# 5) 按时间区间（日志行首是时间戳）
kubectl exec -n $NS $POD -- sh -c "grep '2026-07-16 1[4-5]:' $DIR/app.log"

# 6) 命中过多时先裁再贴
kubectl exec -n $NS $POD -- sh -c "grep '关键字' $DIR/app.log | tail -n 50"

# 7) 历史：先看 archive 有哪些天
kubectl exec -n $NS $POD -- sh -c "ls $DIR/archive/"

# 8) 按 traceId 串全链路（核心排查技能）
#    纯文本文件: traceId 是行内第6段, 直接 grep (可串 app/error/warn 多个文件)
kubectl exec -n $NS $POD -- sh -c "grep 'fd75ebb10a09d443' $DIR/app.log"
#    logstash.log(JSON): 字段名是 trace
kubectl exec -n $NS $POD -- sh -c "grep '\"trace\":\"fd75ebb10a09d443\"' $DIR/logstash.log"
```

如果容器没有 `grep`/`tail`（极少数极简镜像），退化为 `cat` + 在本地用 Bash 工具的 grep 过滤；或换 `busybox` 侧车。guozhi 的镜像目前都带标准 shell 工具。

### 5. 分析并给出结论

输出要**结论导向**，结构如下（按需精简，别八股）：

1. **查了什么**：环境 / 服务 / pod / 日志文件 / 时间范围 / 关键字（一两句）
2. **关键证据**：精挑几条最相关的日志片段（贴关键行，别整段甩 300 行；长异常栈只保留根因 `Caused by:` 那几行）
3. **结论**：问题是什么、在哪一行代码/哪个组件、可能原因
4. **下一步**：建议再查什么文件/关键字、或去代码里看哪段（能给出 `文件:行` 最好）

## 数据库查询（查数据 / 看表结构）

排查中需要核对数据时，用 db-query.py 查目标环境的 MySQL（**本地直连通道**）：

```bash
uv run --no-project --with pymysql --with cryptography python <本skill目录>/scripts/db-query.py <env> <服务名> "SELECT ..."
# 例:
uv run --no-project --with pymysql --with cryptography python <本skill目录>/scripts/db-query.py dev2 guozhi-common-platform "SELECT COUNT(*) FROM approval_instance"
```

- **通道背景（勿回退）**：查询账号有来源 IP 白名单，K8s 集群 pod 来源一律 `ERROR 1045`，`kubectl exec` 借道 db pod 的老通道已废弃；本工具从本机直连，需本机在白名单内（开发机默认在）。
- **配置先行**：凭据按「环境默认 + 服务覆写」存于 `~/.zcode/guozhi/config.json` 的 `db` 节点。退出码 3 = 配置缺失，按 `references/db.md` 的流程向用户收集、写入、验证；不要跳过配置硬查。
- **配置随时可改**：用户说「改 db 配置/换密码/加个服务的库」，直接按 `references/db.md` 的调整流程改对应条目并验证，不用等首次配置的时机。
- **默认只读**：只放行 SELECT/SHOW/DESC/EXPLAIN 且单条语句。确需写入必须先获用户明确同意，再加 `--write`。
- 退出码：0 成功 / 2 用法错误 / 3 配置缺失 / 4 连接失败 / 5 SQL 被拒绝。
- **表结构从 entity 反推**：先 `resolve-repo.sh <服务名>` 定位仓库，`@TableName` 定位 entity；实库 `DESC` 兜底。详见 `references/db.md`。

## 跨服务查代码（workspace 配置）

排查常要跨微服务看代码（traceId 追下游、看 entity 定义、对照接口实现）。**查代码一律直接查本地源码仓库，不要去 maven 本地仓库（~/.m2）翻 jar 包**——guozhi 服务的仓库地址已收集在 `_workspace` 配置里，用 resolve-repo.sh 把服务名解析成本地仓库路径：

```bash
bash <本skill目录>/scripts/resolve-repo.sh <服务名或关键字>
# 例:
bash <本skill目录>/scripts/resolve-repo.sh guozhi-teaching   # → D:/workspace/guozhi-teaching
```

- **首次使用**：退出码 3 = 未配置。问用户「guozhi 仓库都放在哪个目录」，写入 `~/.zcode/guozhi/config.json` 的 `_workspace.roots`；个别不按 `guozhi-<服务名>` 命名或放在别的位置的仓库，往 `_workspace.repos` 加显式映射。完整流程读 `references/workspace.md`。
- **随时调整**：用户说「仓库挪地方了/新 clone 了/目录名不对」，直接改 config.json 的 roots/repos，改完验证即可。
- **退出码**：0 成功（stdout = 仓库路径，一行）/ 3 未配置或未找到 / 6 多候选歧义（stderr 列候选，交用户选或换更精确名字）。

## 安全与边界

- 日志查询都是只读（tail/grep/cat/ls），对集群无副作用，可放心执行；**绝不要执行任何写操作**（不 rm、不重启、不改配置）。若排查需要重启或改配置，只能给出建议，由用户自己操作。
- 数据库查询默认只读白名单；任何写操作（含 `--write` 逃逸口）必须先拿到用户在对话中的明确同意。db 凭据与 workspace 配置同存 `~/.zcode/guozhi/config.json`，该文件绝不写进任何 git 仓库、文档或对话外产物。
- 日志可能含敏感信息（token、手机号、内部地址）。这是用户自己内网环境的排查，正常如实展示给用户本人即可；仅当用户要把日志外发时才提醒脱敏。
- `kubectl exec` 进容器本质是执行命令，保持命令为只读查询。

## 速查：环境 → namespace

| 用户说法 | namespace |
|---------|-----------|
| dev1 | guozhi-dev1 |
| dev2 | guozhi-dev2 |
| dev3 | guozhi-dev3 |
| fat1 | guozhi-fat1 |
| uat | guozhi-uat |

注意：不是每个服务在每个环境都部署。例如 `guozhi-common-platform` 在 dev1 没有，在 dev2/dev3/fat1/uat 都有。定位不到时跨环境搜一遍再告诉用户。
