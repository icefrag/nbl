# nbl

本仓 `skills/` 只保留自研 skill 与 2 个 superpowers 搬运件（`using-git-worktrees`、`verification-before-completion`，原样未改）。其余第三方 skill 一律用 `npx` 从原始来源安装（命令见 `README.md`），**不在本仓做镜像同步**，也不要把上游 skill 搬进 `skills/`。

## 安装与更新

```bash
npx skills@latest add <owner>/<repo> -a zcode claude-code -g -y -s <name...>   # 安装
npx skills@latest update                                                    # 更新全部
npx skills@latest list                                                      # 查看已装
npx skills@latest remove -g -y <name...>                                    # 卸载
```

两条铁律：

1. **命令必须单行**。反斜杠续行只有 bash 认，PowerShell / cmd 会在第一行末尾就执行，`-s` 整段丢失 → 装下仓库内全部 skill（mattpocock 仓共 38 个，含 pr 与 in-progress 件）。
2. **`-s` 不可省**。省略即全选；`--skill '*'` 同理。

安装记录在 `~/.agents/.skill-lock.json`（含每个 skill 的来源仓库与哈希），agent 目录（`~/.zcode/skills`、`~/.claude/skills`）只是分发副本。

## skill 来源

| 来源 | 内容 | 状态 |
|---|---|---|
| 本仓 `icefrag/nbl` | 6 个（4 自研 + 2 superpowers 搬运） | 随仓维护 |
| `mattpocock/skills` | 26 个工程主力 | 上游直装，`update` 跟 |
| `ayghri/i-have-adhd`、`op7418/Humanizer-zh`、`alibaba/open-code-review`、`vercel-labs/skills`（find-skills） | 4 个第三方 | 上游直装 |

上游 mattpocock 仓共 38 个 skill，我们只取 26 个。未收录的 12 个：

- `pr`——无 PR 场景（公司内部业务开发，jkd 直部署），**勿装**
- `git-guardrails-claude-code`、`setup-pre-commit`、`scaffold-exercises`、`migrate-to-shoehorn`（misc）——一次性环境配置类，按需单独装
- `chief-of-staff`、`claude-handoff`、`loop-me`、`setup-ts-deep-modules`、`writing-beats`、`writing-fragments`、`writing-shape`（in-progress）——上游自标 WIP，**勿装**

## 上游查证

- mattpocock skills 本机克隆：`D:\workspace-script\skills`（`skills/engineering`、`skills/productivity`、`skills/misc`、`skills/in-progress`）；上游 main 更新频繁，本机克隆可能落后，用 `git fetch && git log origin/main..main` 看差量
- 官方 superpowers 源码：`D:\workspace-script\superpowers`（`skills/`）——本仓 `using-git-worktrees`、`verification-before-completion` 来自这里
- 核对本仓与上游是否一致：`diff -rq <上游路径> skills/<name>`
