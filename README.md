# nbl

AI 江湖，门派层出不穷，取其精华，去其糟粕，自成一派。

本仓库只保留 6 个 skill：**4 个自研 + 2 个原样搬运自 superpowers**。其余第三方 skill 一律用 `npx` 从原始来源安装，不在本仓做镜像同步——上游更新直接 `npx skills update` 就能拿到，仓库不再背同步的债。

## 目录

- [本仓库维护的 skill](#本仓库维护的-skill)
- [常用 skill 安装命令](#常用-skill-安装命令)
  - [mattpocock/skills（工程主力，26 个）](#mattpocockskills工程主力26-个)
  - [其他第三方（4 个）](#其他第三方4-个)
  - [本仓库 icefrag/nbl（6 个）](#本仓库-icefragnbl6-个)
- [更新与卸载](#更新与卸载)
- [安装位置说明](#安装位置说明)

## 本仓库维护的 skill

| skill | 来源 | 用途 |
|---|---|---|
| `dev-standards` | 自研 | Java 后端开发规范路由表，写/改/review Java 前必读 |
| `deploy` | 自研 | 部署流程（jkd 直部署） |
| `k8s-logs` | 自研 | guozhi 项目 K8s 日志排查 + 数据库只读查询 |
| `code-simplifier` | 自研（改写自 Claude 官方插件） | 代码简化重构（保持功能不变） |
| `using-git-worktrees` | superpowers 搬运 | 大改动隔离工作区（git worktree） |
| `verification-before-completion` | superpowers 搬运 | 宣称完成前必须跑验证命令 |

## 常用 skill 安装命令

前置：`node` 可用。安装器把 skill 存到 `~/.agents/skills`，再分发到各 agent 的 skills 目录（`~/.zcode/skills`、`~/.claude/skills`）。

命令中：

- `-a zcode claude-code`：装到 ZCode 和 Claude Code 两个 agent（只用一个就删掉另一个）
- `-g`：全局安装（所有项目可用）；去掉 `-g` 则装到当前项目
- `-s`：指定 skill 名，可一次列多个；不写则交互式选择
- `-y`：跳过确认

### mattpocock/skills（工程主力，26 个）

一次性装齐：

```bash
npx skills@latest add mattpocock/skills -a zcode claude-code -g -y \
  -s ask-matt code-review codebase-design diagnosing-bugs domain-modeling \
     grill-me grill-with-docs grilling handoff implement implement-spec \
     improve-codebase-architecture prototype research retro \
     setup-matt-pocock-skills tdd teach to-questionnaire to-spec to-tickets \
     triage wait-what wayfinder wizard writing-for-agents
```

单个补装（把 `tdd` 换成任意 skill 名）：

```bash
npx skills@latest add mattpocock/skills -a zcode claude-code -g -s tdd -y
```

按用途分组，方便挑：

| 分组 | skill |
|---|---|
| 需求到交付 | `to-spec` `to-tickets` `implement` `implement-spec` `prototype` `research` |
| 质量把关 | `code-review` `tdd` `diagnosing-bugs` `verification-before-completion`（见本仓） |
| 思考与打磨 | `grill-me` `grill-with-docs` `grilling` `to-questionnaire` `wayfinder` `wait-what` |
| 领域与架构 | `domain-modeling` `codebase-design` `improve-codebase-architecture` |
| 协作收尾 | `handoff` `teach` `retro` `triage` `wizard` `writing-for-agents` |
| 入口/初始化 | `ask-matt`（路由器，先看它选谁） `setup-matt-pocock-skills`（每个仓库跑一次） |

> `setup-matt-pocock-skills` 装完要在目标仓库里跑一次，配置 issue tracker、triage 标签和文档目录。

### 其他第三方（4 个）

```bash
# i-have-adhd：ADHD 友好的输出格式（/i-have-adhd 开启，会话内持续生效）
npx skills@latest add ayghri/i-have-adhd -a zcode claude-code -g -s i-have-adhd -y

# humanizer-zh：去 AI 味的中文改写
npx skills@latest add op7418/Humanizer-zh -a zcode claude-code -g -s humanizer-zh -y

# open-code-review：阿里开源的代码评审
npx skills@latest add alibaba/open-code-review -a zcode claude-code -g -s open-code-review -y

# find-skills：在 skills 生态里搜技能
npx skills@latest add vercel-labs/skills -a zcode claude-code -g -s find-skills -y
```

### 本仓库 icefrag/nbl（6 个）

本仓这 6 个装法同上，源换成本仓：

```bash
npx skills@latest add icefrag/nbl -a zcode claude-code -g -y \
  -s code-simplifier deploy dev-standards k8s-logs \
     using-git-worktrees verification-before-completion
```

## 更新与卸载

```bash
npx skills@latest update           # 更新所有已装 skill（上游改动直接生效）
npx skills@latest list             # 看当前装了什么
npx skills@latest remove -s <name> -g # 卸载单个（全局安装对应 -g）
```

## 安装位置说明

| 路径 | 内容 |
|---|---|
| `~/.agents/skills/<name>` | 技能实体（安装器维护的规范副本，`update` 更新的就是它） |
| `~/.zcode/skills/<name>` | ZCode 读这里 |
| `~/.claude/skills/<name>` | Claude Code 读这里 |
| `~/.zcode/skills/bash` `caveman` `megacave` `ultracave` | ZCode 自带/手动安装，不走 npx |

安装器默认软链到 agent 目录；Windows 上软链建不出来时会自动降级为复制安装（`--copy` 可强制复制）。两种模式下 `npx skills update` 都能把上游改动同步过来。

每个 skill 的来源仓库和哈希记录在 `~/.agents/.skill-lock.json`，可用 `npx skills list` 看当前状态。
