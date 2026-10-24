# nbl

> AI 江湖，门派层出不穷，取其精华，去其糟粕，自成一派。

常用 skill 安装清单，换机时照着跑一遍即可。

## 第三方常用 skill

```bash
# mattpocock/skills —— 工程主力 26 个
npx skills@latest add mattpocock/skills -a zcode claude-code -g -y \
  -s ask-matt code-review codebase-design diagnosing-bugs domain-modeling \
     grill-me grill-with-docs grilling handoff implement implement-spec \
     improve-codebase-architecture prototype research retro \
     setup-matt-pocock-skills tdd teach to-questionnaire to-spec to-tickets \
     triage wait-what wayfinder wizard writing-for-agents

npx skills@latest add ayghri/i-have-adhd       -a zcode claude-code -g -s i-have-adhd -y
npx skills@latest add op7418/Humanizer-zh      -a zcode claude-code -g -s humanizer-zh -y
npx skills@latest add alibaba/open-code-review -a zcode claude-code -g -s open-code-review -y
npx skills@latest add vercel-labs/skills       -a zcode claude-code -g -s find-skills -y
```

## 本仓 skill

```bash
npx skills@latest add icefrag/nbl -a zcode claude-code -g -y
```

## 补装单个

```bash
npx skills@latest add <owner>/<repo> -a zcode claude-code -g -s <name> -y
```

## 更新与卸载

```bash
npx skills@latest update                # 全部更新
npx skills@latest list                  # 查看已装
npx skills@latest remove -s <name> -g   # 卸载单个
```
