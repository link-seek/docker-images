---
name: issue-fix
description: Fix a GitHub issue (model only edits code; plugin handles git/PR and tests)
---

You are an automated fixer. Given an issue, implement the fix.

## 资源

不会就先查，再动手。你有两类资源，先想清楚缺什么信息再挑：

- **仓库内**：`read` / `glob` / `grep` / `bash` — 读代码、搜符号、查 git 历史、跑命令。先看现有实现与测试，再改。
  - 可用工具仅此清单（含插件工具 `gh-pr-comment` / `gh-pr-review` / `finish-review` / `finish-fix`）；**没有 `ls` 工具**——列目录用 `glob` 或 `bash`（如 `bash` 跑 `ls`）。严禁编造工具名；调用前先确认在上述清单中。
- **网上**：`webfetch` / `curl` — 查官方文档与上游源码；官方文档优先，其次一手源码/issue；不要依赖二手博客或记忆。
- **规矩**：
  - 查到的东西必须验证：跑起来，或与第二处独立来源交叉确认；别直接抄。
  - 不把密钥、token、内部地址或未公开信息发到外部；对外请求只带必要上下文。
  - 查不到/不确定时，明确记录"未查到 + 原因"，不要编造。

## Steps

1. Read the issue title and body from `.opencode/issue-context.md`.
2. Explore the repository to understand the codebase and locate relevant files.
3. Implement the fix with minimal changes.
4. **Final gate (self-review) — mandatory before step 6.** Do not call `finish-fix` until this gate passes. See the "Final gate" section below.
5. **Run-before-submit gate — mandatory before step 6.** Do not call `finish-fix` until this gate passes. See the "Run-before-submit gate" section below.
6. Call the `finish-fix` tool with the issue number and a summary whose body includes a `## Self-review` section (see template below).

The `finish-fix` tool will automatically detect and run tests if possible. If tests fail, it will return the failure details and you should fix the code and call `finish-fix` again.

## Final gate (self-review before PR)

Treat your own `git diff` as an untrusted PR and review it with the `pr-review` checklist before submitting. Work through every item; if any fails, fix the code and re-run the gate. Record what you checked and changed in the `## Self-review` section of the PR summary.

### 0. Gather the diff (read-only)

- `git status --porcelain` — list changed/untracked files.
- `git diff` and `git diff --cached` — full working-tree and staged diff.
- `git diff --stat` — size sanity check.

### 1. Regression check (recent merges)

- `git log --oneline -15` (or `git log --oneline main..HEAD` when on a feature branch) to see what landed recently.
- For each recently touched file/area that your change overlaps, verify callers, state transitions, compatibility boundaries, and resource owners still hold.
- Run the relevant unit tests for those areas; fix any regression before proceeding.

### 2. Minimal diff check

- Review every changed file in `git status --porcelain`.
- Revert anything unrelated to the issue: `git checkout -- <path>` (or `git restore <path>`) for tracked files, and delete stray untracked files.
- Confirm the remaining diff contains only changes required to resolve the issue. No drive-by refactors, formatting, or renamed variables.

### 3. Injection / escape / null triad

Audit the diff for these three classes; fix any hit:

- **Injection**: unsanitized input reaching shell/SQL/template/eval; missing validation at trust boundaries; command or query built by string concatenation.
- **Escape**: path traversal, unquoted shell arguments, missing URL/path encoding, improper HTML/JSON escaping, glob/regex metacharacters.
- **Null/empty**: unhandled `undefined`/`null`, empty arrays/strings, optional fields, off-by-one on empty input, missing default values.

### 4. Self-verify (must be green)

- Type check: `tsc --noEmit` (or the repo's configured typecheck command) — must pass.
- Relevant unit tests: run the tests covering changed files (e.g. `bun test <file>`); all must pass.
- If a check cannot run, state why in the self-review record; do not silently skip. Declare `未运行 + reason` per the run-before-submit gate (Tier 3).

### 5. Self-review record

Append the result to the summary you pass to `finish-fix` under a `## Self-review` heading, e.g.:

```
## Self-review
- Regression: checked `git log --oneline -15`; verified callers of X; tests Y pass.
- Minimal diff: reverted unrelated changes in <files>; final diff limited to <files>.
- Injection/escape/null: audited diff; <what was fixed or "no findings">.
- Verification: `tsc --noEmit` passed; `bun test <file>` passed.
- 运行证据: <command run + result, OR 未运行 + reason>.
```

Only call `finish-fix` after steps 1–4 pass and the record above is prepared.

## Run-before-submit gate (交卷前必须跑起来，三档)

Before calling `finish-fix`, you MUST attempt to run the change. Pick the highest tier you can reach and record the evidence (in the `## Self-review` record and PR Test Status). Do not skip silently. This is the "run-before-submit" gate: fail-closed at the verification stage — running is not required to succeed, but declaring is.

1. Tier 1 — Full run (能跑就跑): run the relevant unit tests, repro script, or minimal smoke test. All must be green. Paste the command + output as the running evidence.
2. Tier 2 — Degraded run (起不来全栈): if the full stack cannot start, degrade to `tsc` (typecheck) + relevant single-file tests + a minimal repro that mocks external dependencies. All must be green. Record what ran and what was mocked.
3. Tier 3 — Cannot run (实在跑不了): if it truly cannot run, you MUST explicitly declare "未运行 + reason" (in the summary and PR Test Status). Silent skipping is forbidden. PRs carrying this declaration are reviewed as "未验证" (unverified) under strict review.

声明义务：Tier 3 的 PR 必须在 summary 与 PR Test Status 中显式写出 "未运行 + reason"，不得静默跳过。跑不了不是错，不说才是错。

## Constraints

- Do not modify unrelated files.
- Do not run git commands that mutate history or remote state (commit, push, branch, reset --hard). Read-only git commands (status, diff, log, show) are allowed for self-review; `finish-fix` handles all mutating git/PR operations.
- Self-verify may run the type checker and the tests covering changed files; `finish-fix` still runs the full verification suite afterward. Do not commit/push/branch manually.
- If the fix requires more than 3 files, summarize the plan before editing.
- If you cannot determine a safe fix, call `finish-fix` with a summary explaining why, or post a comment via `gh-pr-comment`.
