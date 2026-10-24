# nbl

> AI 江湖，门派层出不穷，取其精华，去其糟粕，自成一派。

个人 skill 仓库：本仓只收录 6 个 skill（4 自研 + 2 搬运自 superpowers），第三方一律用 `npx` 从原始来源安装、不做镜像同步，上游更新一句 `npx skills update` 搞定。

## 本仓 skill

| skill | 来源 | 用途 |
|---|---|---|
| `dev-standards` | 自研 | Java 后端开发规范路由表，写/改/review Java 前必读 |
| `deploy` | 自研 | 部署流程（jkd 直部署） |
| `k8s-logs` | 自研 | guozhi 项目 K8s 日志排查 + 数据库只读查询 |
| `code-simplifier` | 自研（改写自 Claude 官方插件） | 代码简化重构，功能不变 |
| `using-git-worktrees` | superpowers 搬运 | 大改动隔离工作区 |
| `verification-before-completion` | superpowers 搬运 | 宣称完成前必须先跑验证 |

---

## 安装 skill

统一用 [vercel-labs/skills](https://github.com/vercel-labs/skills) 安装器（需 Node ≥ 22）：skill 存入 `~/.agents/skills`，再分发到各 agent 目录。常用参数：

| 参数 | 含义 |
|---|---|
| `-a zcode claude-code` | 装到哪些 agent，按需删减 |
| `-g` | 全局安装；省略则装到当前项目 |
| `-s <name...>` | 指定 skill，可列多个；省略则交互选择 |
| `-y` | 跳过确认 |

### mattpocock/skills（26 个，工程主力）

```bash
npx skills@latest add mattpocock/skills -a zcode claude-code -g -y \
  -s ask-matt code-review codebase-design diagnosing-bugs domain-modeling \
     grill-me grill-with-docs grilling handoff implement implement-spec \
     improve-codebase-architecture prototype research retro \
     setup-matt-pocock-skills tdd teach to-questionnaire to-spec to-tickets \
     triage wait-what wayfinder wizard writing-for-agents
```

补装单个（`<name>` 换成 skill 名）：

```bash
npx skills@latest add mattpocock/skills -a zcode claude-code -g -s <name> -y
```

| 用途 | skill |
|---|---|
| 需求 → 交付 | to-spec · to-tickets · implement · implement-spec · prototype · research |
| 质量把关 | code-review · tdd · diagnosing-bugs |
| 思考打磨 | grill-me · grill-with-docs · grilling · to-questionnaire · wayfinder · wait-what |
| 领域与架构 | domain-modeling · codebase-design · improve-codebase-architecture |
| 协作收尾 | handoff · teach · retro · triage · wizard · writing-for-agents |
| 入口 | ask-matt · setup-matt-pocock-skills |

> `ask-matt` 是这套 skill 的路由器；`setup-matt-pocock-skills` 需在目标仓库跑一次（配置 issue tracker、triage 标签、文档目录）。

### 其他第三方（4 个）

```bash
npx skills@latest add ayghri/i-have-adhd       -a zcode claude-code -g -s i-have-adhd -y       # ADHD 友好输出
npx skills@latest add op7418/Humanizer-zh      -a zcode claude-code -g -s humanizer-zh -y      # 去 AI 味中文改写
npx skills@latest add alibaba/open-code-review -a zcode claude-code -g -s open-code-review -y  # 阿里开源代码评审
npx skills@latest add vercel-labs/skills       -a zcode claude-code -g -s find-skills -y       # 生态内搜技能
```

### 本仓（icefrag/nbl，6 个）

```bash
npx skills@latest add icefrag/nbl -a zcode claude-code -g -y \
  -s code-simplifier deploy dev-standards k8s-logs \
     using-git-worktrees verification-before-completion
```

### 存放位置

| 位置 | 说明 |
|---|---|
| `~/.agents/skills/` | 技能实体，`update` 的更新对象 |
| `~/.zcode/skills/`、`~/.claude/skills/` | 各 agent 读取处 |

Windows 上软链失败会自动降级为复制安装（`--copy` 可强制），两种模式下 `update` 均能同步上游改动。

---

## 更新与卸载

```bash
npx skills@latest update                # 全部更新
npx skills@latest list                  # 查看已装
npx skills@latest remove -s <name> -g   # 卸载单个（全局安装带 -g）
```

每个 skill 的来源仓库与哈希记录在 `~/.agents/.skill-lock.json`。
