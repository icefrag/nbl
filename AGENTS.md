# nbl

本仓 skills/ 只保留自研 skill 与 2 个 superpowers 搬运件（`using-git-worktrees`、`verification-before-completion`，原样未改）。其余第三方 skill 一律用 `npx` 从原始来源安装（安装命令见 `README.md`），**不在本仓做镜像同步**，也不要把上游 skill 搬进 `skills/`。

已改为 npx 直装、不再同步进本仓的上游：

- mattpocock/skills（`https://github.com/mattpocock/skills`）——26 个常用 skill，`npx skills@latest add mattpocock/skills -a zcode claude-code -g -s <name...> -y`；更新用 `npx skills@latest update`

上游源码仅作查证参考（本机路径）：

- mattpocock skills 源码：`D:\workspace-script\skills`（`skills/engineering`、`skills/productivity`）
- 官方 superpowers 源码：`D:\workspace-script\superpowers`（`skills/`）——本仓 `using-git-worktrees`、`verification-before-completion` 来自这里

历史同步排除项（上游有但我们不要，勿再搬入）：

- `pr`：无 PR 场景（公司内部业务开发，jkd 直部署），已于 8.3.24 后删除
