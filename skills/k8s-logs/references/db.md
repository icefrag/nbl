# 数据库查询权威参考（guozhi 各环境微服务）

> SKILL.md 的「数据库查询」节是入口；本篇是通道原理、配置 schema、首次配置流程、entity 反推规则的完整版。
> 通道与拓扑为 2026-09-22 实测；基础设施若变动，以实测绘为准。

## 执行通道（已实测验证）

- **执行方式**：`kubectl exec` 进 db pod 的 `mysql` 容器（自带 MySQL 5.7 客户端），`-e` 非交互执行 SQL。本地机器没有任何 mysql 客户端，也不需要装。
- **dev1/dev2/dev3**：业务库就在集群内——每环境一个 MySQL statefulset（`db-mysql-shadow-0`），稳定地址用 DNS：`mysql-headless.guozhi-<env>`，端口 3306（pod IP 会随重调度变化，配置里写 DNS 不写 IP）。
- **fat1/uat**：集群内没有 mysql pod，库在集群外。通道是借道 dev1 的 db pod 跨环境连接——**网络是否可达未验证**，不通时只能让用户提供查询入口（跳板/可直连的白名单机器）。
- **验证方法**（无凭据也能测）：用假凭据探测，返回 `ERROR 1045 Access denied` 即证明 DNS 解析、网络、mysqld 认证层全通，只差真凭据。

实测拓扑快照：

| 环境 | 库位置 | host（配置建议值） | port |
|------|--------|-------------------|------|
| dev1 | 集群内 | `mysql-headless.guozhi-dev1` | 3306 |
| dev2 | 集群内 | `mysql-headless.guozhi-dev2` | 3306 |
| dev3 | 集群内 | `mysql-headless.guozhi-dev3` | 3306 |
| fat1 | 集群外 | 用户提供 | 用户提供 |
| uat  | 集群外 | 用户提供 | 用户提供 |

## 配置文件

- 路径：`~/.zcode/guozhi/config.json` 的 **`db` 节点**（用户主目录，**不入任何 git 仓库**——nbl 仓库要推 GitHub，凭据绝不能进 repo；同文件的 `_workspace` 节点管仓库定位，见 `references/workspace.md`）。
- 结构：**环境默认（`_default`）+ 服务覆写**。服务条目可覆写任意字段；dev 环境通常服务条目只写 `database`，fat1/uat 通常每个服务写完整条目。

```json
{
  "db": {
    "dev2": {
      "_default": {
        "host": "mysql-headless.guozhi-dev2",
        "port": 3306,
        "user": "dev查询账号",
        "password": "***"
      },
      "guozhi-common-platform": { "database": "guozhi_common_platform" },
      "guozhi-teaching":        { "database": "guozhi_teaching" }
    },
    "fat1": {
      "guozhi-teaching": {
        "host": "172.x.x.x", "port": 3306,
        "user": "专用账号", "password": "***",
        "database": "guozhi_teaching"
      }
    }
  }
}
```

## 首次配置与随时调整（agent 执行）

触发时机：`db-query.sh` 退出码 3（配置缺失）走首次配置；用户说「改 db 配置 / 换密码 / 加个服务的库 / 换账号」走同样的写入+验证步骤，只是跳过探测、直接改对应条目。配置不是一次性的，随时可改，改完立即生效。

1. **判断缺什么**：整个环境缺（先配 `_default`）还是只缺服务库名（走第 3 步）。
2. **配 `_default`（dev1/2/3 可半自动）**：host/port 不用问用户，先探测：
   ```bash
   kubectl get endpoints -n guozhi-<env> -o wide | grep -i mysql
   # dev2 实例输出: mysql-headless  172.18.0.153:3306  → host 写 mysql-headless.guozhi-dev2
   ```
   然后只向用户要 **user / password**（一般一个环境一个查询账号）。fat1/uat 的 host/port/user/password 都要问用户。
3. **配服务库名**：有 `_default` 凭据后，主动探测候选库名，减少用户输入：
   ```bash
   bash <本skill目录>/scripts/db-query.sh <env> <svc> "SHOW DATABASES" --database information_schema
   # 或 SHOW DATABASES LIKE '%teaching%'
   ```
   把候选列给用户确认（guozhi 惯例：库名 = 服务名去 `guozhi-` 前缀后加下划线，如 `guozhi_teaching`，但以 SHOW 出来的为准）。
4. **写入并验证**：更新 config.json → 立即 `SELECT 1` 验证 → 告知用户已保存。
5. **凭据纪律**：凭据只写 `~/.zcode/guozhi/config.json`；绝不写进代码、文档、commit message 或日志贴片。用户在对话里发来的密码不要在回显中原样复述。

## db-query.sh 用法与语义

```bash
bash <本skill目录>/scripts/db-query.sh <env> <service> <SQL> [--database <名>] [--write] [--dry-run]
```

- 结果走 stdout，诊断/告警走 stderr（与 resolve-pod.sh 同约定）。
- 退出码：`0` 成功 / `2` 用法错误 / `3` 配置缺失（走首次配置流程）/ `4` 连接或通道失败 / `5` SQL 被只读白名单拒绝。
- **默认只读**：只放行 `SELECT/SHOW/DESC/DESCRIBE/EXPLAIN` 开头的**单条**语句（含 `;` 的多语句直接拒绝，防止借白名单首词夹带写操作）。
- **`--write` 逃逸口**：造测试数据等确需写入的场景，必须**先在对话中获得用户明确同意**，再加 `--write` 执行。绝不为省一次提问而默认带 `--write`。
- **`--dry-run`**：只打印解析出的通道/目标/SQL（密码打码），不执行。配置疑似不对或 SQL 含中文想核对时先用。
- `--database`：临时指定库名，优先于配置（如探测阶段借 `information_schema`）。
- 已知注意：SQL 里含中文字面量经 Windows→kubectl→容器多层传递，若匹配异常，用 `--dry-run` 核对，或改用 `hex`/`unhex` 比对、或按英文/ID 列过滤。

## 表结构：从代码 entity 反推

先定位服务仓库：`resolve-repo.sh <服务名>`（workspace 配置与匹配规则见 `references/workspace.md`；仓库确实不在本地时问用户要路径）。**不要凭空猜表结构**：

1. **定位 entity**：guozhi 用 MyBatis-Plus，表名显式声明在类上：
   ```bash
   grep -rl '@TableName("approval_instance")' --include='*.java' /d/workspace/guozhi-common-platform
   ```
   已知 entity 类名反查表名、已知表名反查代码，都是这一条 grep。
2. **读字段**：Java 驼峰字段 → 下划线列（`instanceId` → `instance_id`）；字段上的 Javadoc 注释就是列语义，比 `DESC` 的裸列名信息量大得多。
3. **公共字段**：`BaseEntity`（`guozhi-platform-framework` 的 `com.guozhi.api.framework.model.entity.BaseEntity`）只含 `id` / `createTime` / `updateTime`；`createdBy` / `updatedBy` / `isDeleted` 由各 entity 子类自行声明（`isDeleted` 带 `@TableLogic`，查询时 MyBatis-Plus 会自动拼 `is_deleted = 0`，手写 SQL 核对数据时要记得带上）。
4. **实库兜底**：entity 反推的是「代码以为的结构」，权威以实库为准，两者冲突以实库为准并提示用户（可能是迁移没跑）：
   ```bash
   bash skills/k8s-logs/scripts/db-query.sh dev2 guozhi-common-platform "DESC approval_instance"
   bash skills/k8s-logs/scripts/db-query.sh dev2 guozhi-common-platform "SHOW CREATE TABLE approval_instance"
   ```
