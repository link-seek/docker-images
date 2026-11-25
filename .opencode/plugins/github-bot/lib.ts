/**
 * Testable helpers extracted from the github-bot plugin.
 */

export function randomNonce(): string {
  const bytes = new Uint8Array(16)
  crypto.getRandomValues(bytes)
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")
}

export function fenceUntrusted(content: string, nonce: string): string {
  return (
    `===== BEGIN UNTRUSTED PR CONTENT ${nonce} =====\n` +
    `${content}\n` +
    `===== END UNTRUSTED PR CONTENT ${nonce} =====`
  )
}

export function validateIssueNumber(issueNumber: unknown): { valid: boolean; error?: string } {
  if (!issueNumber || typeof issueNumber !== "number" || !Number.isInteger(issueNumber) || issueNumber <= 0) {
    return { valid: false, error: "Error: invalid issue number" }
  }
  return { valid: true }
}

export function validateBranchName(branch: string): { valid: boolean; error?: string } {
  if (!/^[a-zA-Z0-9._\/-]+$/.test(branch) || branch === "main" || branch === "master") {
    return { valid: false, error: `Error: invalid or protected branch name: ${branch}` }
  }
  return { valid: true }
}

export function isProtectedBranch(branch: string): boolean {
  return branch === "main" || branch === "master"
}
// --- runShell (extracted for testing) ---

export async function runShell(
  cmd: string,
  cwd?: string,
  spawnFn?: (cmd: string, cwd: string) => Promise<{ stdout: string; stderr: string; code: number }>,
): Promise<{ stdout: string; stderr: string; code: number }> {
  const workDir = cwd || process.cwd()
  if (spawnFn) {
    return spawnFn(cmd, workDir)
  }
  try {
    const proc = Bun.spawn(["bash", "-c", cmd], {
      cwd: workDir,
      stdout: "pipe",
      stderr: "pipe",
    })
    const stdout = await new Response(proc.stdout).text()
    const stderr = await new Response(proc.stderr).text()
    const code = await proc.exited
    return { stdout: stdout.trim(), stderr: stderr.trim(), code }
  } catch {
    const { execSync } = await import("node:child_process")
    try {
      const stdout = execSync(cmd, { cwd: workDir, encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] })
      return { stdout: stdout.trim(), stderr: "", code: 0 }
    } catch (e: any) {
      return { stdout: "", stderr: e.stderr?.toString() ?? e.message, code: e.status ?? 1 }
    }
  }
}

// --- ghApi (extracted for testing) ---

export function githubApiBase(): string {
  const raw = process.env.GITHUB_API_URL || "https://api.github.com"
  return raw.replace(/\/+$/, "")
}

export async function ghApi(
  method: string,
  path: string,
  body?: Record<string, unknown>,
  fetchFn?: typeof fetch,
  token?: string,
  apiBase?: string,
): Promise<any> {
  const t = token ?? process.env.GITHUB_TOKEN
  const _fetch = fetchFn ?? fetch
  const base = (apiBase || githubApiBase()).replace(/\/+$/, "")
  const res = await _fetch(`${base}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${t}`,
      "Content-Type": "application/json",
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
    },
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) {
    const text = await res.text()
    throw new Error(`GitHub API ${method} ${path}: ${res.status} ${text}`)
  }
  return res.json()
}

// --- finish-fix core logic (extracted for testing) ---

export interface FinishFixDeps {
  runShell: (cmd: string) => Promise<{ stdout: string; stderr: string; code: number }>
  ghApi: (method: string, path: string, body?: Record<string, unknown>) => Promise<any>
  repo: string
}

export async function finishFixCore(
  issueNumber: number,
  summary: string | undefined,
  deps: FinishFixDeps,
): Promise<string> {
  const results: string[] = []

  // Safety: validate issue number
  const issueCheck = validateIssueNumber(issueNumber)
  if (!issueCheck.valid) return issueCheck.error!

  // Safety: never operate on protected branches
  const currentBranch = (await deps.runShell("git branch --show-current")).stdout
  if (currentBranch === "main" || currentBranch === "master") {
    return "Error: cannot commit on protected branch (main/master). Checkout a feature branch first."
  }

  // 1. Check for changes
  const diff = await deps.runShell("git diff --stat && git diff --cached --stat")
  const status = await deps.runShell("git status --porcelain")
  if (!status.stdout) {
    return "No changes detected. Nothing to commit."
  }
  results.push(`Changes detected:\n${diff.stdout || status.stdout}`)

  // 1.6. Run verification (tests) if possible
  const verifyCmd = process.env.VERIFY_COMMAND || null
  let testStatus = "not_run"
  let testOutput = ""
  if (verifyCmd) {
    const verifyResult = await runVerification(verifyCmd, deps.runShell)
    testStatus = verifyResult.status
    testOutput = verifyResult.output
    if (verifyResult.status === "failed") {
      return `Tests failed:\n${verifyResult.output}\n\nFix the tests and call finish-fix again.`
    }
    if (verifyResult.status === "passed") {
      results.push(`Tests passed: ${verifyCmd}`)
    } else {
      results.push(`Tests could not run: ${verifyResult.output}`)
    }
  } else {
    const hasPkg = (await deps.runShell("test -f package.json && echo yes || echo no")).stdout === "yes"
    const hasMake = (await deps.runShell("test -f Makefile && echo yes || echo no")).stdout === "yes"
    const hasPyproject = (await deps.runShell("test -f pyproject.toml && echo yes || echo no")).stdout === "yes"
    const hasCargo = (await deps.runShell("test -f Cargo.toml && echo yes || echo no")).stdout === "yes"
    const hasGo = (await deps.runShell("test -f go.mod && echo yes || echo no")).stdout === "yes"
    let pkgScripts: { test?: string; verify?: string } = {}
    if (hasPkg) {
      try {
        const pkgContent = await deps.runShell("cat package.json")
        const pkg = JSON.parse(pkgContent.stdout)
        pkgScripts = pkg.scripts || {}
      } catch { /* ignore */ }
    }
    const cmd = detectTestCommand(
      { hasPackageJson: hasPkg, hasMakefile: hasMake, hasPyproject: hasPyproject, hasCargoToml: hasCargo, hasGoMod: hasGo },
      pkgScripts,
      undefined,
    )
    if (cmd) {
      const verifyResult = await runVerification(cmd, deps.runShell)
      testStatus = verifyResult.status
      testOutput = verifyResult.output
      if (verifyResult.status === "failed") {
        return `Tests failed:\n${verifyResult.output}\n\nFix the tests and call finish-fix again.`
      }
      if (verifyResult.status === "passed") {
        results.push(`Tests passed: ${cmd}`)
      } else {
        results.push(`Tests could not run: ${verifyResult.output}`)
      }
    } else {
      testStatus = "not_run"
      results.push("No test command detected. CI will validate.")
    }
  }

  // 2. Commit
  const commitMsg = `fix: resolve issue #${issueNumber}`
  const commit = await deps.runShell(`git add -A && git commit -m "${commitMsg}"`)
  if (commit.code !== 0) {
    return `Commit failed: ${commit.stderr}`
  }
  results.push("Committed.")

  // 3. Check for existing open PRs
  let existingPR: { number: number; head: string } | null = null
  try {
    const prs = await deps.ghApi("GET", `/repos/${deps.repo}/pulls?state=open`)
    for (const pr of prs) {
      if (pr.body && pr.body.includes(`Closes #${issueNumber}`)) {
        existingPR = { number: pr.number, head: pr.head.ref }
        break
      }
    }
  } catch { /* non-fatal */ }

  const branch = existingPR ? existingPR.head : `fix/issue-${issueNumber}`

  // Safety: validate branch name
  const branchCheck = validateBranchName(branch)
  if (!branchCheck.valid) {
    return branchCheck.error!
  }

  // 4. Push
  if (existingPR) {
    await deps.runShell(`git fetch origin ${branch}`)
    await deps.runShell(`git checkout ${branch}`)
  } else {
    await deps.runShell(`git checkout -b ${branch}`)
  }
  const push = await deps.runShell(`git push --force-with-lease origin ${branch}`)
  if (push.code !== 0) {
    const push2 = await deps.runShell(`git push -u origin ${branch}`)
    if (push2.code !== 0) {
      return `Push failed: ${push.stderr}\n${push2.stderr}`
    }
  }
  results.push(`Pushed to ${branch}.`)

  // 5. Create or update PR
  if (existingPR) {
    try {
      const testStatusLine = testStatus === "passed" ? `\n\n## Test Status\n✅ Passed` : testStatus === "not_run" ? `\n\n## Test Status\n⚠️ Not run (no test environment)` : `\n\n## Test Status\n❌ ${testStatus}`
      await deps.ghApi("POST", `/repos/${deps.repo}/issues/${existingPR.number}/comments`, {
        body: `Updated with new fix attempt.\n\n${summary ?? ""}${testStatusLine}`,
      })
      results.push(`Updated existing PR #${existingPR.number}`)
    } catch (e: any) {
      results.push(`PR comment failed: ${e.message}`)
    }
  } else {
    try {
      const prData = await deps.ghApi("POST", `/repos/${deps.repo}/pulls`, {
        title: `fix: resolve issue #${issueNumber}`,
        body: `Closes #${issueNumber}\n\n${summary ?? ""}\n\n## Test Status\n${testStatus === "passed" ? "✅ Passed" : testStatus === "not_run" ? "⚠️ Not run (no test environment)" : `❌ ${testStatus}`}${testOutput ? ` — ${testOutput.slice(0, 300)}` : ""}`,
        head: branch,
        base: "main",
        draft: true,
      })
      results.push(`Created PR #${prData.number}: ${prData.html_url}`)
    } catch (e: any) {
      results.push(`PR creation failed: ${e.message}`)
    }
  }

  return results.join("\n")
}

// --- Test detection and verification (extracted for testing) ---

export interface VerifyResult {
  command: string | null
  status: "passed" | "failed" | "not_run" | "error"
  output: string
}

export function detectTestCommand(
  files: { hasPackageJson: boolean; hasMakefile: boolean; hasPyproject: boolean; hasCargoToml: boolean; hasGoMod: boolean },
  packageJsonScripts?: { test?: string; verify?: string },
  envVerifyCommand?: string,
): string | null {
  // 1. Explicit env var (highest priority)
  if (envVerifyCommand && envVerifyCommand.trim()) {
    return envVerifyCommand.trim()
  }
  // 2. package.json scripts
  if (files.hasPackageJson && packageJsonScripts) {
    if (packageJsonScripts.verify) return packageJsonScripts.verify
    if (packageJsonScripts.test && packageJsonScripts.test !== 'echo "Error: no test specified" && exit 1') {
      return packageJsonScripts.test
    }
  }
  // 3. Makefile
  if (files.hasMakefile) return "make test"
  // 4. Python
  if (files.hasPyproject) return "pytest"
  // 5. Rust
  if (files.hasCargoToml) return "cargo test"
  // 6. Go
  if (files.hasGoMod) return "go test ./..."
  return null
}

export async function runVerification(
  cmd: string | null,
  runShellFn: (cmd: string) => Promise<{ stdout: string; stderr: string; code: number }>,
): Promise<VerifyResult> {
  if (!cmd) {
    return { command: null, status: "not_run", output: "No test command detected" }
  }
  try {
    const result = await runShellFn(cmd)
    if (result.code === 0) {
      return { command: cmd, status: "passed", output: result.stdout || "Tests passed" }
    }
    return { command: cmd, status: "failed", output: result.stderr || result.stdout || "Tests failed" }
  } catch (e: any) {
    return { command: cmd, status: "error", output: e.message || "Failed to run tests" }
  }
}

// --- Laminar tracing re-exports (#79) ---
export * from "./trace"

export function formatTestStatus(result: VerifyResult): string {
  switch (result.status) {
    case "passed":
      return `✅ Tests passed — \`${result.command}\`\n${result.output.slice(0, 500)}`
    case "failed":
      return `❌ Tests failed — \`${result.command}\`\n${result.output.slice(0, 500)}`
    case "not_run":
      return `⚠️ Tests not run — ${result.output}. CI will validate.`
    case "error":
      return `⚠️ Tests could not run — ${result.output}. CI will validate.`
  }
}
