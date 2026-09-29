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

**归档与保留**：所有 logback 文件**按小时滚动**为 `archive/<file>.log.<yyyyMMddHH>.gz`，仅保留 **72 小时**（约 3 天）。3 天前的日志本地没有，只能去 ELK——`logstash.log` 的 JSON 格式就是给 ELK 采集用的。查「昨天/某时段」先 `ls archive/` 看有哪些归档小时，再 zgrep（模板见第 4 节）。

**⚠ request.log 已废弃**：当前 logback 配置里**没有 request appender**，磁盘上残留的 `request.log` 是旧版本遗留、不再写入（实测 mtime 能停在半个月前）。请求日志实际由 `REQUEST-LOGGER` 写入 **app.log + logstash.log**——排查请求别再查 request.log。

**JVM 层日志**（`gc.log`/`gc.log.0~4`/`start.log` 等）由 JVM 启动参数输出，不归 logback 管，文件名/滚动由 JVM 决定。

### 日志格式速记（grep 不抓瞎）

排查时八成要 grep，这几个格式细节决定了你的 grep 能不能命中，先记牢：

- **纯文本文件**（`app/error/warn/info/time.log`）行格式：`[时间] - 级别 - logger - appName - class[line] - traceId - spanId - thread - msg`（` - ` 分隔共 9 段）。**traceId 是第 6 段**，直接 `grep '<traceId>'` 就能串全链路；中文正常显示，可 grep 中文关键字。
- **`logstash.log` 是 JSON**，字段名是 `trace`/`span`/`rest`。按 traceId 用 `grep '"trace":"<id>"'`；但 **`rest` 里的中文被 unicode 转义**（如「请求结束」存成 `请求结束`），所以 **grep 中文关键字在 logstash.log 里打不中**——要 grep 中文，只能用 app/error 等纯文本文件。
- `logLevel=INFO`，**DEBUG/TRACE 默认不输出**，别去找 DEBUG 日志。

> 需要精确判断「某条日志到底去了哪个文件」（比如某个 logger 写哪、第三方库 INFO 在哪）时，读 `references/logback-routing.md`——里面有完整的 logger→appender 路由表。

### 4. 抓日志（命令模板）

**核心原则一：非交互。** 绝不带 `-it`，绝不 `tail -f`（不会结束）。用 `kubectl exec ... -- sh -c "..."` 把命令一次性传进去。

**核心原则二：轻量。** 命令跑在用户的服务容器里，要防的是**内存 O(n) 的命令、无界输出、永不结束的命令**（CPU/IO 代价的诚实评估见本节末尾）。具体做到：**输出有界**（凡可能多行输出的 grep 一律 `| tail -n` 收口；`grep -c` 输出只有一个数字，免收口）、**内存 O(1)**（只用流式的 ls/tail/grep/zgrep，`head -c` 仅作红线里的逃生口）、**单次线性扫描**（扫完即退，不反复全文件扫）。过滤与裁剪都在 pod 内管道里完成，只把最终几十~几百行经 kubectl 传回——绝不把大块原始日志拉回本地再筛。

**第 0 步永远是先探大小**（O(1)，一条 ls 决定后续策略）：

```bash
POD=<脚本返回的 pod>; NS=<ns>; SVC=<服务名>; DIR=/data/log/$SVC
kubectl exec -n $NS $POD -- sh -c "ls -lh $DIR"
```

- 几 MB~几十 MB（error/warn/time/start/gc 常态）→ 小文件，直接查；
- 上百 MB~GB 级（app/info/logstash 高峰常态）→ 走大文件策略，避免反复全文件扫描。

**小文件模板**（直接查，输出仍要收口）：

```bash
# 1) 先看命中规模（便宜，先跑）
kubectl exec -n $NS $POD -- sh -c "grep -c 'ERROR' $DIR/error.log"

# 2) 抓尾部最新
kubectl exec -n $NS $POD -- sh -c "tail -n 300 $DIR/error.log"

# 3) grep 关键字 + 后文上下文（异常栈通常在报错行之后）；tail 收口=只看最近几次，要看最早一次换 head
kubectl exec -n $NS $POD -- sh -c "grep -n -A 30 'NullPointerException' $DIR/error.log | tail -n 120"

# 4) 多关键字 OR / 大小写不敏感；一批关键字合并成一次 grep，别每个词各扫一遍
kubectl exec -n $NS $POD -- sh -c "grep -E -i 'timeout|refused' $DIR/error.log | tail -n 100"
```

**按 traceId 串全链路**（核心排查技能；traceId 唯一，全文件扫一次的成本可接受——但重试风暴下单个 traceId 命中也可能上百行，照常收口）：

```bash
# 纯文本文件: traceId 是行内第6段, 直接 grep (可串 app/error/warn 多个文件)
kubectl exec -n $NS $POD -- sh -c "grep 'fd75ebb10a09d443' $DIR/app.log | tail -n 100"
# logstash.log(JSON): 字段名是 trace
kubectl exec -n $NS $POD -- sh -c "grep '\"trace\":\"fd75ebb10a09d443\"' $DIR/logstash.log | tail -n 100"
```

**大文件模板**（app/info/logstash 超百 MB 时）：logback 按时间顺序追加，**越新的日志越靠近文件尾**——查最近的事从尾部裁着扫，查更早的事去 archive 拿对应小时的 gz（单个小得多）：

```bash
# 5) 只扫尾部 N 行再过滤（N 按日志量估：20 万行约覆盖最近几十分钟到几小时；查最早一次换 head）
kubectl exec -n $NS $POD -- sh -c "tail -n 200000 $DIR/app.log | grep '关键字' | tail -n 50"

# 6) 时间区间（日志行首是时间戳）：最近的从尾部裁；更早的（昨天/前天）直接查归档
kubectl exec -n $NS $POD -- sh -c "tail -n 500000 $DIR/app.log | grep '2026-09-29 1[4-5]:' | tail -n 100"

# 7) 归档：先按文件类型过滤出有哪些小时，再 zgrep（流式解压扫描，同样收口）
kubectl exec -n $NS $POD -- sh -c "ls -lh $DIR/archive/ | grep 'app.log' | tail -n 10"
kubectl exec -n $NS $POD -- sh -c "zgrep '关键字' $DIR/archive/app.log.2026092910.gz | tail -n 50"
```

**尾部裁扫没命中 ≠ 没有**（N 不够大——日志量大的服务 20 万行可能只覆盖几分钟；或目标时段在文件更早处、尚未滚入归档）。按顺序兜底：① 加大 N 重扫；② `grep -c` 确认全文件里到底有没有（一次线性扫描，输出 1 个数字）；③ 确认有但被 N 裁掉了，改跑带收口的全文件 grep（`grep '关键字' $DIR/app.log | tail -n 100`）；④ 时段更早则查归档。

**轻量红线**（会冲击 pod 内存或传输量，禁止）：

- `cat` 大文件、`kubectl cp` 拉当前活跃大文件或整个日志目录——输出与传输量不可控。**单个几 MB 的归档 gz 允许 `kubectl cp` 拉回本地分析**（pod 里没有 zgrep 时的兜底）。极简镜像没有 grep/tail 时，也只允许 `head -c 500000 $DIR/xx.log` 裁剪后再传，或换同服务其他副本的 pod（guozhi 镜像都带标准 shell 工具，基本走不到这条）。
- 可能多行输出的 grep 不带 `| tail`/`| head` 收口——命中万级时输出刷爆传输（`grep -c` 输出仅一个数字，不受此限）。
- `sort`/`awk`/`uniq -c` 等全量聚合——内存 O(n)，**大文件上**会顶爆 pod 内存；几 MB 的小文件做异常分布统计可以用。
- `grep -r` 递归整个 /data/log——扫描量不可控，先 `ls` 明确文件再查。

**不必过度保守，但要认清 CPU 代价**：grep/tail 流式扫描、内存 O(1)、扫完即退——会出事的只有上面黑名单（内存 O(n) 的聚合、无界输出、永不结束的命令）。真正的代价在 CPU 和磁盘 IO：pod 的 CPU limit 实测多为 **500m，由 grep 与服务 JVM 共享**，GB 级大文件的全文件扫描会让服务**肉眼可见地被挤占几秒到几十秒**——这正是全文件扫描（含 `grep -c`）只放在兜底链、且要确认时段确在文件内才跑的原因，日常一律尾部裁扫 + 归档单文件。**无 CPU limit 的 pod**（dev3 的 api-gateway/api-main/gateway 系即如此）更没有 cgroup 兜底，打满的核直接与节点所有进程争抢，更要克制。

### 5. 分析并给出结论

输出要**结论导向**，结构如下（按需精简，别八股）：

1. **查了什么**：环境 / 服务 / pod / 日志文件 / 时间范围 / 关键字（一两句）
2. **关键证据**：精挑几条最相关的日志片段（贴关键行，别整段甩 300 行；长异常栈只保留根因 `Caused by:` 那几行）
3. **结论**：问题是什么、在哪一行代码/哪个组件、可能原因
4. **下一步**：建议再查什么文件/关键字、或去代码里看哪段（能给出 `文件:行` 最好）

证据不足时，考虑查库取证补齐后再下结论（何时值得查见「数据库查询」节）。

## 数据库查询（查数据 / 看表结构）

日志证明的是「代码走到了哪、抛了什么」，数据能提供日志给不出的证据。排查时结合案情判断值不值得查库取证：**是否值得查由你判断**，纯代码 bug 不必查；判断有价值就查——只读 SELECT 与查日志同级、无副作用，无需先请示。典型值得查的案情：

- 日志说记录不存在/状态没流转，要看库里到底有没有、停在哪一步
- 用户反馈操作后没生效，需核对是否真的落库
- error.log 出现 SQL 异常（BadSqlGrammar、数据类型转换、连接池报错）
- 结论需要数据佐证：量级、状态分布、某类单据占比
- 行为由配置/字典数据驱动，疑似配置把行为带偏

用 db-query.py 查目标环境的 MySQL（**本地直连通道**）：

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

- 日志查询都是只读（ls/tail/grep/zgrep），且一律按第 4 节轻量模板执行——输出有界、内存 O(1)，对 pod 的 CPU/内存无冲击，可放心执行；**绝不要执行任何写操作**（不 rm、不重启、不改配置）。若排查需要重启或改配置，只能给出建议，由用户自己操作。
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
