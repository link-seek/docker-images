import { Plugin } from "@opencode/plugin"
import { validateIssueNumber, validateBranchName, runShell, ghApi, finishFixCore } from "./lib"
import { laminarEnabled, initLaminar, flushSoon, withTimeout } from "./trace"

/**
 * OpenCode v2 GitHub Bot — self-contained server plugin.
 *
 * Model only edits code. All git/PR/GitHub operations are hardcoded in tools.
 * Tools: gh-pr-comment, gh-pr-review, finish-review, finish-fix
 * Hook: nonce fence on prompt
 */




export default Plugin.define({
  id: "github-bot",

  async setup(ctx) {
    const repo = process.env.GITHUB_REPOSITORY ?? ""

    // --- GitHub write tools -------------------------------------------------
    await ctx.tool.transform((editor) => {
      editor.namespace({ name: "gh", description: "GitHub operations" })

      editor.add({
        name: "gh-pr-comment",
        description: "Post a comment on a PR or issue",
        input: {
          type: "object",
          properties: {
            number: { type: "integer", description: "PR or issue number" },
            body: { type: "string", description: "Comment body (markdown)" },
          },
          required: ["number", "body"],
          additionalProperties: false,
        },
        execute: async (input, context) => {
          const { number, body } = input as { number: number; body: string }
          try {
            const data = await ghApi("POST", `/repos/${repo}/issues/${number}/comments`, { body })
            return { content: `Comment posted: ${data.html_url ?? "ok"}` }
          } catch (e: any) {
            return { content: `Failed: ${e.message}` }
          }
        },
      })

      editor.add({
        name: "gh-pr-review",
        description: "Submit a PR review (COMMENT/APPROVE/REQUEST_CHANGES)",
        input: {
          type: "object",
          properties: {
            number: { type: "integer", description: "PR number" },
            body: { type: "string", description: "Review body" },
            event: { type: "string", enum: ["COMMENT", "APPROVE", "REQUEST_CHANGES"] },
          },
          required: ["number", "body", "event"],
          additionalProperties: false,
        },
        execute: async (input, context) => {
          const { number, body, event } = input as { number: number; body: string; event: string }
          try {
            const data = await ghApi("POST", `/repos/${repo}/pulls/${number}/reviews`, { body, event })
            return { content: `Review submitted: ${data.html_url ?? data.id ?? "ok"}` }
          } catch (e: any) {
            return { content: `Failed: ${e.message}` }
          }
        },
      })

      editor.add({
        name: "finish-review",
        description: "Finalize a PR review. Call this after you have analyzed the PR and are ready to post your review. Pass your review body and optional inline comments.",
        input: {
          type: "object",
          properties: {
            prNumber: { type: "integer", description: "PR number" },
            body: { type: "string", description: "Top-level review body" },
            inlineComments: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  path: { type: "string" },
                  line: { type: "integer" },
                  body: { type: "string" },
                },
                required: ["path", "line", "body"],
              },
              description: "Optional inline comments",
            },
          },
          required: ["prNumber", "body"],
          additionalProperties: false,
        },
        execute: async (input, context) => {
          const { prNumber, body, inlineComments } = input as {
            prNumber: number
            body: string
            inlineComments?: Array<{ path: string; line: number; body: string }>
          }
          const results: string[] = []

          // Post inline comments
          if (inlineComments && inlineComments.length > 0) {
            for (const c of inlineComments) {
              try {
                await ghApi("POST", `/repos/${repo}/pulls/${prNumber}/comments`, {
                  body: c.body,
                  path: c.path,
                  line: c.line,
                  commit_id: (await ghApi("GET", `/repos/${repo}/pulls/${prNumber}`)).head.sha,
                })
                results.push(`inline: ${c.path}:${c.line}`)
              } catch (e: any) {
                results.push(`inline failed: ${c.path}:${c.line} — ${e.message}`)
              }
            }
          }

          // Post top-level review
          try {
            const data = await ghApi("POST", `/repos/${repo}/pulls/${prNumber}/reviews`, {
              body,
              event: "COMMENT",
            })
            results.push(`review: ${data.html_url ?? data.id ?? "ok"}`)
          } catch (e: any) {
            results.push(`review failed: ${e.message}`)
          }

          return { content: results.join("\n") }
        },
      })

      editor.add({
        name: "finish-fix",
        description: "Finalize an issue fix. Call this after you have implemented and tested the fix. This tool handles all git operations (commit, push, branch management, PR creation) internally.",
        input: {
          type: "object",
          properties: {
            issueNumber: { type: "integer", description: "Issue number being fixed" },
            summary: { type: "string", description: "Brief summary of what was changed and why" },
          },
          required: ["issueNumber"],
          additionalProperties: false,
        },
        execute: async (input, context) => {
          const { issueNumber, summary } = input as { issueNumber: number; summary?: string }
          const repo = process.env.GITHUB_REPOSITORY ?? ""
          const result = await finishFixCore(issueNumber, summary, {
            runShell,
            ghApi: (method, path, body) => ghApi(method, path, body, undefined, process.env.GITHUB_TOKEN),
            repo,
          })
          return { content: result }
        },
      })
    })

    // NOTE: Prompt text is trusted (comes from workflow, not PR/issue content).
    // Untrusted PR/issue content is fenced in the context file (pr-context.md / issue-context.md).
    // Do NOT fence the prompt here — it would make the model refuse to follow instructions.

    // --- Laminar tracing (#79) -------------------------------------------------
    // NOTE: the agent.task span itself is emitted by scripts/report-task.ts
    // AFTER `opencode run` exits (the agent process cannot be relied on to
    // flush: it may process.exit(), skipping beforeExit handlers).
    // Here we only keep a best-effort flush backstop for any spans the
    // agent process did manage to create.
    // Run-once guard: beforeExit refires whenever the loop drains; without
    // the guard the handler would reschedule itself forever and hang exit.
    // The in-flight promise is shared so concurrent signals/beforeExit
    // await the same flush instead of starting new ones.
    let exitFlush: Promise<void> | null = null
    const flushOnce = () => {
      if (!exitFlush) exitFlush = flushSoon()
      return exitFlush
    }
    try {
      if (laminarEnabled()) {
        await initLaminar()
        // beforeExit: schedule flush work; the pending I/O keeps the loop
        // alive until done (bounded by the timeout + run-once guard).
        process.on("beforeExit", flushOnce)
        process.on("SIGTERM", () => { flushOnce().then(() => process.exit(0)) })
        process.on("SIGINT", () => { flushOnce().then(() => process.exit(0)) })
      }
    } catch {
      // tracing must never block main flow
    }

    await ctx.storage.set("loaded", true)
    console.log(`github-bot plugin loaded in OpenCode ${ctx.app.version}`)
  },
})