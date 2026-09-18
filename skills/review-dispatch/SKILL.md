---
name: review-dispatch
description: >
  Dispatch strategy for code review: small diffs get reviewed inline in the
  main session; larger diffs dispatch one reviewer subagent fed a ready-made
  review package (diff + intent + test results) so it never forages for
  context. Use when executing a code review or pre-merge review, or when
  dispatching a review or re-review subagent. Triggers on "review", "代码审查",
  "评审", "合并前审查". Review standards themselves follow the code-review skill.
---

# Review Dispatch

## Overview

Slow reviews are rarely the five-axis checklist's fault — the cost is the
reviewer agent's cold-start foraging: deriving the review range with git,
pulling the full diff, and crawling surrounding code file by file. This skill
governs only **how a review is dispatched**. What to check, and how findings
are phrased, comes from the [code-review](../code-review/SKILL.md) skill — read in its
original wording, never paraphrased.

Two dispatch principles:

1. **Review inline when you can.** The five-axis checklist does not need an
   isolated subcontext to work.
2. **When you must dispatch, hand over a ready-made review package.** The
   caller already knows the scope and the intent — never make the reviewer
   re-derive them.

## Step 1: Establish the Review Target

Resolve the target exactly as the code-review skill's "Review Process" section
specifies (upstream diff / base diff, plus uncommitted changes; no git — ask
the user), then run `git diff --stat` to size it.

## Step 2: Choose the Execution Mode

**Inline review (no subagent)** — only when BOTH hold:

- The change is small: ≤ ~200 changed lines ("reviewable in one sitting" per
  the code-review skill's change sizing; `--stat` tells at a glance);
- This session is not the author of the code and not an SDD coordinator — no
  self-review blind spot, and no coordinator context that must be preserved
  for driving the work.

Inline means walking the code-review skill's full process and producing the same
severity labels (Critical / unprefixed Required / Nit / Optional / FYI) and
file:line citations.

**Exception: inside SDD, always dispatch.** The coordinator's context is
reserved for driving the work — this overrides the inline conditions.

## Step 3: Prepare the Review Package Before Dispatching

A review package = commit list + `git diff --stat` + `git diff -U10`, written
to one file so the reviewer reads the whole change in one call:

```bash
{ git log --oneline "$BASE..$HEAD"; echo; git diff --stat "$BASE..$HEAD"; echo; git diff -U10 "$BASE..$HEAD"; } > "/tmp/review-$(git rev-parse --short "$BASE")..$(git rev-parse --short "$HEAD").diff"
```

- When the change is mostly uncommitted work, fold `git diff` / `git diff
  --cached` output into the same package.
- Inside SDD, don't hand-roll it: use subagent-driven-development's
  `scripts/review-package PLAN BASE HEAD` (handles the per-task BASE and
  names re-review files per range).
- **Re-review rounds must use an incremental package**:
  `review-package <previous review's base SHA> HEAD` — review the fix diff
  only, never the full diff again.

The agent prompt must carry three things; missing any one sends the reviewer
foraging:

1. Absolute path to the review package file;
2. Intent: a one-sentence description, or a link to the plan/spec;
3. Tests already run and their results (if none, run them first or say so).

Also resolve the code-review skill's `SKILL.md` path at dispatch time and put it
in the prompt — the reviewer reads the original standard from the file, not
a paraphrase of it.

## Step 4: Dispatch Template

```
Subagent (general-purpose):
  description: "Code review <base7>..<head7>"
  prompt: |
    You are a code reviewer. First read the review package: <PACKAGE_PATH>
    (commit list, stat summary, diff with context). That single read IS your
    view of the change: do not re-run git commands, do not crawl the
    codebase. Only when a hunk cannot be judged without code outside the
    package, make one focused check per named risk, and state both the risk
    and what you checked in your report. Your review is read-only: never
    mutate the working tree, the index, or HEAD.

    ## Intent
    <INTENT>

    ## Verification Already Run
    <TEST_RESULTS>

    ## Review Standard
    First read the code-review skill in full and follow it exactly:
    <REVIEW_SKILL_PATH>
    Apply its five axes (correctness, readability, architecture, security,
    performance), its severity labels, and its verdict format. If the file
    cannot be read, fall back to those five axes with severity labels:
    Critical (blocks merge) / unprefixed Required / Nit / Optional / FYI —
    every finding with a file:line reference and a concrete fix. A few
    high-conviction findings beat a long list. End with a verdict:
    Approve or Request changes, plus 1-2 sentences of reasoning.
```

## Red Flags

- Dispatching a reviewer that then runs `git diff` itself and hunts for the
  spec — the caller failed
- A re-review round that re-reviews the full diff instead of the increment
  since the previous review's base
- An SDD coordinator reviewing inline to save time — it burns the context
  needed to drive the work, and self-review has blind spots
- A reviewer spawning further subagents to split the five axes — the axes
  overlap heavily; that is a 5x redundant read of the same diff (and the
  upstream templates forbid it)
- Paraphrasing the review standard into the dispatch prompt instead of
  pointing the reviewer at the code-review skill's original text
