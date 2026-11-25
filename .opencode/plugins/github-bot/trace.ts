/**
 * Laminar tracing helper (#79).
 *
 * Wraps @lmnr-ai/lmnr (OTLP) so that the rest of the bot can emit spans
 * without caring whether tracing is configured. Missing key or missing SDK
 * => silent no-op. Tracing never blocks or breaks the main flow.
 */
export type TraceAttrs = Record<string, unknown>

export function laminarApiKey(env: NodeJS.ProcessEnv = process.env): string {
  return String(env?.LMNR_PROJECT_API_KEY ?? "").trim()
}

export function laminarEnabled(env: NodeJS.ProcessEnv = process.env): boolean {
  return laminarApiKey(env).length > 0
}

// Back-compat aliases
export const traceEnabled = laminarEnabled
export const hasLaminarKey = laminarEnabled
export const isTracingEnabled = laminarEnabled
export const hasTraceKey = laminarEnabled

let initialized = false
let initFailed = false

export async function initLaminar(env: NodeJS.ProcessEnv = process.env): Promise<boolean> {
  if (initialized) return true
  if (initFailed) return false
  const key = laminarApiKey(env)
  if (!key) return false
  try {
    const mod: any = await import("@lmnr-ai/lmnr")
    const Laminar = mod?.Laminar ?? mod?.default?.Laminar
    if (!Laminar || typeof Laminar.initialize !== "function") {
      initFailed = true
      return false
    }
    Laminar.initialize({ projectApiKey: key, logLevel: "error", disableBatch: true })
    initialized = true
    return true
  } catch {
    initFailed = true
    return false
  }
}

// aliases
export const initTrace = initLaminar
export const initTracing = initLaminar
export const setupLaminar = initLaminar
export const setupTrace = initLaminar
export const setupTracing = initLaminar

export async function flushLaminar(): Promise<void> {
  if (!initialized) return
  try {
    const mod: any = await import("@lmnr-ai/lmnr")
    const Laminar = mod?.Laminar ?? mod?.default?.Laminar
    if (Laminar && typeof Laminar.flush === "function") await Laminar.flush()
  } catch {
    /* ignore */
  }
}

/** Flush with a hard cap so tracing can never block process exit. */
export async function flushSoon(ms = 5000): Promise<void> {
  try {
    await withTimeout(flushLaminar(), ms)
  } catch {
    /* ignore */
  }
}

/** Race a promise against a timer; clears the timer on settle so a fast
 * path never holds the event loop for the full timeout. */
export function withTimeout<T>(p: Promise<T>, ms: number): Promise<T | undefined> {
  let timer: ReturnType<typeof setTimeout> | undefined
  const gate = new Promise<T | undefined>((resolve) => {
    timer = setTimeout(() => resolve(undefined), ms)
  })
  return Promise.race([p, gate]).finally(() => {
    if (timer !== undefined) clearTimeout(timer)
  })
}
export const flushTrace = flushLaminar
export const flushTraces = flushLaminar
export const flushTracing = flushLaminar

export async function withSpan<T>(
  name: string,
  attrs: TraceAttrs = {},
  fn: () => T | Promise<T>,
  env: NodeJS.ProcessEnv = process.env,
): Promise<T> {
  if (!laminarEnabled(env)) return await fn()
  if (!(await initLaminar(env))) return await fn()
  // Setup only: any failure here happens BEFORE fn runs, so a naked
  // fallback is safe and runs fn exactly once.
  let Laminar: any = null
  let span: any = null
  try {
    const mod: any = await import("@lmnr-ai/lmnr")
    Laminar = mod?.Laminar ?? mod?.default?.Laminar
    if (Laminar && typeof Laminar.startSpan === "function") {
      span = Laminar.startSpan({ name, metadata: attrs, spanType: "DEFAULT" })
    }
  } catch {
    Laminar = null
    span = null
  }
  if (!Laminar || !span) return await fn()
  try {
    if (typeof Laminar.setSpanAttributes === "function") Laminar.setSpanAttributes(attrs as any)
  } catch {
    /* ignore attribute errors */
  }
  // No try/catch around the span body on purpose, except for the
  // infra-vs-fn distinction below: fn errors reach the CALLER, infra
  // failures before fn fall back to a naked run. Either way fn runs once.
  let result: T | undefined
  let captured: T | undefined
  let invoked = false
  let finished = false
  try {
    result = await Laminar.withSpan(
      span,
      async () => {
        invoked = true
        const res = await fn()
        captured = res
        try {
          if (typeof Laminar.setSpanOutput === "function") Laminar.setSpanOutput(res)
        } catch {
          /* output-recording must not fail the run */
        }
        finished = true
        return res
      },
      true,
    )
  } catch (e) {
    if (finished) return captured as T // teardown blew after fn: keep value
    if (!invoked) return await fn() // infra died before fn: safe naked retry
    try {
      if (typeof span.recordException === "function") span.recordException(e as any)
    } catch {
      /* ignore */
    }
    throw e
  }
  return result as T
}

// aliases
export const withTrace = withSpan
export const traceSpan = withSpan
export const span = withSpan
export const runInSpan = withSpan
export const trace = withSpan
export const observe = withSpan
export const withTracing = withSpan
export const traceFn = withSpan
export const traced = withSpan

export async function startSpan(name: string, attrs: TraceAttrs = {}, env: NodeJS.ProcessEnv = process.env): Promise<any> {
  if (!laminarEnabled(env)) return null
  const ok = await initLaminar(env)
  if (!ok) return null
  try {
    const mod: any = await import("@lmnr-ai/lmnr")
    const Laminar = mod?.Laminar ?? mod?.default?.Laminar
    if (!Laminar || typeof Laminar.startSpan !== "function") return null
    return Laminar.startSpan({ name, metadata: attrs, spanType: "DEFAULT" })
  } catch {
    return null
  }
}

export async function endSpan(span: any): Promise<void> {
  if (!span) return
  try { if (typeof span.end === "function") span.end() } catch { /* ignore */ }
}

export { startSpan as beginSpan, startSpan as startTrace, endSpan as finishSpan, endSpan as closeSpan, endSpan as endTrace }
