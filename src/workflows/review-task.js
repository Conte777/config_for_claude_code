export const meta = {
  name: 'review-task',
  description: 'Review all MRs of a Jira task: 6 lenses + a task-completeness agent over diffs+clones, then an opus summarizer. Heavy tasks (>=3 MR) run code-reading agents on a 1M-context model.',
  phases: [
    { title: 'Review' },
    { title: 'Match', model: 'sonnet' },
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
// In MR-URL mode the dir is review-task-mrs.* -> no key -> generic header.
const KEY = (WORK.match(/review-task-([A-Z]+-\d+)/) || [])[1] || ''
const HEADER = KEY ? `Review задачи ${KEY}` : 'Review merge requests'

// Heavy task (>=3 MR): the fetch-hook tags the WORK dir with "-heavy". On heavy,
// code-reading agents (lenses, completeness, summarizer) run on a 1M-context model
// so they don't hit "Prompt is too long" while following imports across clones.
const HEAVY = WORK.includes('-heavy.')
const HEAVY_MODEL = 'claude-opus-4-8[1m]'
// Appended to lens/completeness prompts on heavy: read surgically, don't gulp clones.
const HEAVY_NOTE = `\n\nHEAVY TASK — read economically: НЕ читай файлы целиком и не открывай клоны "на разведку". Через \`Grep\` найди конкретные определения/вызовы/использования для проверки reachability и \`Read\` только нужные участки. Диффы — основное доказательство; в клоны лезь точечно, не залпом.`

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

// 6 lenses. Each lens's role + domain checklist lives in its own agent file
// (src/agents/review-<key>.md, symlinked to ~/.claude/agents), invoked by
// agentType below. This prompt carries only the shared, task-specific context
// (paths, output contract); the lens persona comes from the agent definition.
const LENSES = ['code', 'architecture', 'security', 'performance', 'concurrency', 'over-engineering']

const taskPrompt = `Review one Jira task spread across several merge requests (possibly in different repositories). Your review lens (role + what to hunt for) is defined by your agent prompt — stay strictly within it.

Sources (read with Read/Grep, absolute paths):
- Manifest: ${WORK}/manifest.json — array of {repo, iid, clonePath, diffPath, source_branch, web_url, claudeMd}.
- Diffs: ${WORK}/diffs/*.diff (one per MR).
- Full code (shallow clones): ${WORK}/repos/* — clonePath from the manifest (may be empty if the clone failed).
- Repo conventions: \`<clonePath>/CLAUDE.md\` when manifest's claudeMd is true — the repo's rules and DELIBERATE quirks. Read it BEFORE judging that repo.

Read manifest.json first. For each MR, study its diff, then OPEN the full code in clonePath and investigate: follow imports, callers, and related files to confirm a problem is real and actually reachable before flagging it.

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
const runLens = async (key) => {
  // over-engineering only: hand it the task text so requirement-justified complexity
  // isn't flagged. The task.md path is known here, not in the agent .md, so the
  // context add-on lives in the workflow. Other lenses keep the bare taskPrompt.
  let prompt = key === 'over-engineering' && KEY
    ? `${taskPrompt}\n\nContext — what the task actually required: \`${WORK}/task.md\` (its description + comments). Complexity that this requirement genuinely demands is NOT over-engineering; only flag complexity beyond what the task asks for.`
    : taskPrompt
  if (HEAVY) prompt += HEAVY_NOTE
  const opts = { label: `lens:${key}`, phase: 'Review', schema: FINDINGS, model: HEAVY ? HEAVY_MODEL : 'sonnet', agentType: `review-${key}` }
  let r = await agent(prompt, opts)
  if (!r) r = await agent(prompt, opts) // 1 retry on a dropped stream
  return { lens: key, findings: (r && r.findings) || [] }
}

// Completeness agent (jira-only): reads task.md requirements and reports what the
// MRs left unbuilt. Same shape as runLens so it batches alongside the lenses.
const completenessPrompt = `Check whether this Jira task's MRs actually deliver what the task asked for. Your role (scope/coverage check, not defect hunting) is defined by your agent prompt.

Requirements source: \`${WORK}/task.md\` — the task's title, description, and comments. This is what was asked.
What was built (read with Read/Grep, absolute paths):
- Manifest: ${WORK}/manifest.json — array of {repo, iid, clonePath, diffPath, source_branch, web_url, claudeMd}.
- Diffs: ${WORK}/diffs/*.diff (one per MR).
- Full code (shallow clones): ${WORK}/repos/* — clonePath from the manifest.

Extract the concrete requirements from task.md, then for each check the diffs and the cloned code. Report ONLY requirements that are missing or partial — fully delivered ones produce no finding. Later comments in task.md override the original description when they conflict.

Each finding's fields — write title/why/explanation in RUSSIAN, keep code/identifiers/paths in English:
- severity: "warning" = a stated requirement is not done at all; "suggestion" = partial, ambiguous, or unconfirmed.
- repo, iid (from manifest, best-effort; "" if the gap spans no single MR), file (where the work belongs), line ("" if N/A).
- title: short headline of the missing/partial item.
- why: the requirement (quote/paraphrase task.md) and what is missing.
- explanation: plain language — what wasn't done and why it matters.

If task.md is absent, states no checkable requirements, or everything is covered → return {"findings": []}.`

const runCompleteness = async () => {
  const prompt = HEAVY ? completenessPrompt + HEAVY_NOTE : completenessPrompt
  const opts = { label: 'completeness', phase: 'Review', schema: FINDINGS, model: HEAVY ? HEAVY_MODEL : 'sonnet', agentType: 'review-completeness' }
  let r = await agent(prompt, opts)
  if (!r) r = await agent(prompt, opts) // 1 retry on a dropped stream
  return { lens: 'completeness', findings: (r && r.findings) || [] }
}

// Batch lenses + (jira-only) completeness through the same concurrency cap.
const reviewThunks = LENSES.map((k) => () => runLens(k))
if (KEY) reviewThunks.push(() => runCompleteness())
const lensResults = []
for (let i = 0; i < reviewThunks.length; i += LENS_CONCURRENCY) {
  lensResults.push(...await parallel(reviewThunks.slice(i, i + LENS_CONCURRENCY)))
}

const all = lensResults
  .filter(Boolean)
  .flatMap((r) => r.findings.map((f) => ({ ...f, lens: r.lens })))

if (all.length === 0) {
  return `# ${HEADER}\n\n✅ Чисто — линзы (${LENSES.join(', ')}) не нашли проблем в изменённом коде.`
}

// STAGE 1.5 — Match (cheap sonnet): which findings did humans already raise in MR
// comments? One agent reads the raw discussions so opus never sees them. A null
// result (matcher died) leaves every finding's comment null — nothing is lost.
phase('Match')
all.forEach((f, i) => { f.index = i })
const VERDICTS = {
  type: 'object',
  required: ['verdicts'],
  properties: {
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        required: ['index', 'covered', 'author', 'quote', 'resolved'],
        properties: {
          index: { type: 'integer' },
          covered: { type: 'boolean' },
          author: { type: 'string' },
          quote: { type: 'string' },
          resolved: { type: 'boolean' },
        },
      },
    },
  },
}
const matchPrompt = `Match each automated review finding against the human comments already left on its MR.

Findings (JSON; "index" is the stable id, "comment" if present is irrelevant — ignore it):
${JSON.stringify(all.map((f) => ({ index: f.index, repo: f.repo, iid: f.iid, file: f.file, title: f.title, why: f.why })))}

Manifest: ${WORK}/manifest.json — each MR has a discussionsPath to its human comments. Follow your agent prompt.

Return {"verdicts": [...]} with one entry {index, covered, author, quote, resolved} per finding above.`
const matched = await agent(matchPrompt, { label: 'comment-match', phase: 'Match', agentType: 'review-comment-match', schema: VERDICTS })
for (const f of all) f.comment = null
if (matched && matched.verdicts) {
  for (const v of matched.verdicts) {
    const f = all.find((x) => x.index === v.index)
    if (f && v.covered) f.comment = { author: v.author, quote: v.quote, resolved: v.resolved }
  }
}

// STAGE 2 — summarizer (opus): adversarially validate, dedup, recalibrate, format
phase('Summarize')
const summaryPrompt = `You are the lead reviewer consolidating findings from ${LENSES.length} specialized lenses on one Jira task's MRs.
Code and manifest: ${WORK}/manifest.json, ${WORK}/diffs/*, ${WORK}/repos/* (read with Read/Grep).

Draft findings (JSON; "lens" = which lens reported it):
${JSON.stringify(all)}

Some findings carry \`comment = {author, quote, resolved}\` — a human already raised this in the MR comments (a lens still found it, so the code is likely NOT fixed yet). Do NOT read the raw comments yourself — trust the field. Such findings go in their OWN section "💬 Уже поднято в комментариях МР", never in the severity sections. On dedupe, keep \`comment\` on the merged finding (if any of the merged drafts had one).

Findings with \`lens = "completeness"\` are NOT code defects — they are requirements from the task that the MRs left missing or only partially done. They live by different rules: refute-by-reachability does NOT apply (there is no "trigger" — the point is something is absent). Validate them differently: confirm the gap is real by checking \`${WORK}/task.md\` (what was asked) against the diffs and clones (what was built); drop a finding only if the requirement IS actually delivered or task.md never asked for it. Survivors go in their OWN section "📋 Покрытие задачи", never in the severity sections. They can still dedupe against each other, but do NOT merge a completeness gap with a code-defect finding.

Do this:
1. VALIDATE (adversarial): for each finding open the file:line in its clonePath and actively try to REFUTE it — is it actually reachable? is there a guard upstream? does the trigger really exist? Also check the clone's CLAUDE.md (when present): drop any finding that contradicts a documented convention or deliberate pattern (manual DI, load-bearing typos, etc.). Drop anything you cannot confirm directly from the code. Be strict: a wrong finding is worse than a dropped one.
2. DEDUPE: merge findings about the same place (even across lenses) into one entry; list the lenses; tag the source as <repo>#<iid>.
3. RECALIBRATE severity on the same scale (critical = fix before merge; warning = fix soon; suggestion = optional).
4. If a draft's technical detail was wrong but the underlying issue is real, correct it.

Return ONLY the report (no preamble), written in RUSSIAN, code/identifiers/paths in English, EXACTLY in this Markdown format:

# ${HEADER}

> **Итог:** N critical · M warning · K suggestion · P уже в комментариях · Q пропусков по задаче

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

## 💬 Уже поднято в комментариях МР

### 1. <короткий заголовок>
- **Где:** \`<repo>#<iid>\` — \`path/to/file.go:line\`
- **Проблема:** <технический механизм и триггер>
- **Комментарий:** @username «короткая цитата» — resolved / не исправлено
- **Линзы:** code

## 📋 Покрытие задачи

### 1. <короткий заголовок пропущенного требования>
- **Где:** \`<repo>#<iid>\` — \`path/to/file.go:line\` (или место, где работа ожидалась)
- **Требование:** <что задача просила — цитата/пересказ task.md>
- **Чего не хватает:** <что не сделано или сделано частично>

Formatting rules:
- Omit a section entirely if it has no findings (including the "уже поднято" and "Покрытие задачи" sections, and drop the matching "· P уже в комментариях" / "· Q пропусков по задаче" from Итог when that count is 0).
- Keep each finding tight — no walls of text; one clear sentence per field.
- If nothing survives validation, return only: "# ${HEADER}\\n\\n✅ Чисто — подтверждённых проблем нет."`

return await agent(summaryPrompt, { label: 'summarizer', phase: 'Summarize', model: HEAVY ? HEAVY_MODEL : 'opus' })
