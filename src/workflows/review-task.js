export const meta = {
  name: 'review-task',
  description: 'Review all MRs of a Jira task: 6 lenses over diffs+clones, then an opus summarizer',
  phases: [
    { title: 'Review' },
    { title: 'Summarize', model: 'opus' },
  ],
}

// WORK dir prepared by the review-task-fetch.sh hook (manifest + diffs + clones).
const WORK = args
if (!WORK || typeof WORK !== 'string') {
  log('review-task: no WORK path in args — nothing to review')
  return 'review-task: ошибка — не передан путь WORK (fetch-хук не отработал?).'
}

// Jira key from the WORK dir name (review-task-<KEY>.xxxxxx) for the report header.
const KEY = (WORK.match(/review-task-([A-Z]+-\d+)/) || [])[1] || ''

const FINDINGS = {
  type: 'object',
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['severity', 'repo', 'iid', 'file', 'title', 'why', 'explanation'],
        properties: {
          severity: { type: 'string', enum: ['critical', 'warning', 'suggestion'] },
          repo: { type: 'string' },
          iid: { type: 'string' },
          file: { type: 'string' },
          line: { type: 'string' },
          title: { type: 'string' },
          why: { type: 'string', description: 'technical mechanism + trigger/reachability (the evidence)' },
          explanation: { type: 'string', description: 'plain-language: what goes wrong and why it matters, no jargon' },
        },
      },
    },
  },
}

// 6 lenses (no tests lens, per plan). code reuses the code-reviewer agent.
const LENSES = [
  { key: 'code', role: 'senior software engineer', focus: 'Correctness bugs, mishandled errors, edge cases, nil/undefined/null derefs, off-by-one, wrong control flow, and language-specific footguns.' },
  { key: 'architecture', role: 'senior software architect', focus: 'Module boundaries, coupling, duplication, leaky abstractions, deviation from the repo\'s existing patterns, and broken cross-repo/API contracts.' },
  { key: 'security', role: 'senior security engineer', focus: 'Injection (SQL/command/XSS), unsafe deserialization, secrets in code, broken authn/authz, missing input validation at trust boundaries, and sensitive data leaking via errors/logs.' },
  { key: 'performance', role: 'senior performance engineer', focus: 'N+1 queries, redundant allocations/work, inefficient queries or loops, and blocking calls on a hot path.' },
  { key: 'concurrency', role: 'senior concurrency engineer', focus: 'Data races, shared mutable state without synchronization, deadlocks, wrong context/cancellation handling, and goroutine/thread leaks.' },
  { key: 'over-engineering', role: 'pragmatic senior engineer who hates needless complexity', focus: 'Needless abstractions, speculative flexibility, reinvented stdlib, dead layers, and boilerplate that should be deleted.' },
]

const lensPrompt = (role, focus) => `You are a ${role} doing an adversarial code review of one Jira task spread across several merge requests (possibly in different repositories).
Adversarial stance: assume a junior wrote these changes. Do NOT trust the code — your job is to find real defects, not to approve it.

Sources (read with Read/Grep, absolute paths):
- Manifest: ${WORK}/manifest.json — array of {repo, iid, clonePath, diffPath, source_branch, web_url, claudeMd}.
- Diffs: ${WORK}/diffs/*.diff (one per MR).
- Full code (shallow clones): ${WORK}/repos/* — clonePath from the manifest (may be empty if the clone failed).
- Repo conventions: \`<clonePath>/CLAUDE.md\` when manifest's claudeMd is true — the repo's rules and DELIBERATE quirks. Read it BEFORE judging that repo.

Read manifest.json first. For each MR, study its diff, then OPEN the full code in clonePath and investigate: follow imports, callers, and related files to confirm a problem is real and actually reachable before flagging it.

Your lens: ${focus}

Hard rules:
- Flag ONLY problems introduced by the CHANGED code (the diffs). Surrounding code is context only.
- Respect patterns documented in the repo's CLAUDE.md (e.g. manual DI instead of FX, load-bearing typos that must NOT be "fixed") — do not report them as defects.
- EVIDENCE, not speculation: every finding must name the concrete mechanism and the trigger/reachability path (which input or call sequence makes it happen). If you cannot point at the exact code that fails, do not report it.
- Severity: "critical" = breaks prod, corrupts data, or is exploitable — must fix before merge; "warning" = real defect or risk — fix soon; "suggestion" = optional improvement.
- Do NOT report: style/formatting/naming; "add error handling/logging/tests" where it already exists or isn't needed; hypotheticals with no trigger; anything you are unsure about. When in doubt, stay silent — a missed nitpick beats a false alarm. A clean change is a valid result (return no findings).

Each finding's fields — write title/why/explanation in RUSSIAN, keep code/identifiers/paths in English:
- severity, repo, iid (from manifest), file, line (string, "" if N/A)
- title: short headline.
- why: the technical mechanism and trigger — the evidence.
- explanation: plain language for a non-expert — what actually goes wrong and why it matters, no jargon.

No findings → return {"findings": []}.`

// STAGE 1 — lenses in batches of LENS_CONCURRENCY (barrier: summarizer needs all
// findings deduped). The local ANTHROPIC_BASE_URL proxy drops streams when all 6
// run at once (-> api_error), and a synchronous retry hits the same peak; capping
// concurrency keeps the peak survivable, with one retry for stray drops.
phase('Review')
const LENS_CONCURRENCY = 3
const runLens = async (l) => {
  const opts = { label: `lens:${l.key}`, phase: 'Review', schema: FINDINGS, model: 'sonnet', ...(l.agentType ? { agentType: l.agentType } : {}) }
  let r = await agent(lensPrompt(l.role, l.focus), opts)
  if (!r) r = await agent(lensPrompt(l.role, l.focus), opts) // 1 retry on a dropped stream
  return { lens: l.key, findings: (r && r.findings) || [] }
}
const lensResults = []
for (let i = 0; i < LENSES.length; i += LENS_CONCURRENCY) {
  lensResults.push(...await parallel(LENSES.slice(i, i + LENS_CONCURRENCY).map((l) => () => runLens(l))))
}

const all = lensResults
  .filter(Boolean)
  .flatMap((r) => r.findings.map((f) => ({ ...f, lens: r.lens })))

if (all.length === 0) {
  return `# Review задачи ${KEY}\n\n✅ Чисто — линзы (${LENSES.map((l) => l.key).join(', ')}) не нашли проблем в изменённом коде.`
}

// STAGE 2 — summarizer (opus): adversarially validate, dedup, recalibrate, format
phase('Summarize')
const summaryPrompt = `You are the lead reviewer consolidating findings from ${LENSES.length} specialized lenses on one Jira task's MRs.
Code and manifest: ${WORK}/manifest.json, ${WORK}/diffs/*, ${WORK}/repos/* (read with Read/Grep).

Draft findings (JSON; "lens" = which lens reported it):
${JSON.stringify(all)}

Do this:
1. VALIDATE (adversarial): for each finding open the file:line in its clonePath and actively try to REFUTE it — is it actually reachable? is there a guard upstream? does the trigger really exist? Also check the clone's CLAUDE.md (when present): drop any finding that contradicts a documented convention or deliberate pattern (manual DI, load-bearing typos, etc.). Drop anything you cannot confirm directly from the code. Be strict: a wrong finding is worse than a dropped one.
2. DEDUPE: merge findings about the same place (even across lenses) into one entry; list the lenses; tag the source as <repo>#<iid>.
3. RECALIBRATE severity on the same scale (critical = fix before merge; warning = fix soon; suggestion = optional).
4. If a draft's technical detail was wrong but the underlying issue is real, correct it.

Return ONLY the report (no preamble), written in RUSSIAN, code/identifiers/paths in English, EXACTLY in this Markdown format:

# Review задачи ${KEY}

> **Итог:** N critical · M warning · K suggestion

## 🔴 Critical

### 1. <короткий заголовок>
- **Где:** \`<repo>#<iid>\` — \`path/to/file.go:line\`
- **Проблема:** <технический механизм и триггер — что именно и при каких условиях ломается>
- **Простыми словами:** <объяснение без жаргона: что это значит и чем грозит>
- **Линзы:** code, security

## 🟠 Warning

### 1. <...>
- (те же четыре поля, своя нумерация)

## 🟢 Suggestion

### 1. <...>
- (те же четыре поля)

Formatting rules:
- Omit a severity section entirely if it has no confirmed findings.
- Keep each finding tight — no walls of text; one clear sentence per field.
- If nothing survives validation, return only: "# Review задачи ${KEY}\\n\\n✅ Чисто — подтверждённых проблем нет."`

const report = await agent(summaryPrompt, { label: 'summarizer', phase: 'Summarize', model: 'opus' })
return report
