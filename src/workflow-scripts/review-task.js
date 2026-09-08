export const meta = {
  name: 'review-task',
  description: 'Review all MRs of a Jira task: 6 lenses + a task-completeness agent over diffs+clones, per-finding validation, then an opus summarizer.',
  phases: [
    { title: 'Review', model: 'opus[1m]' },
    { title: 'Dedupe', model: 'sonnet[1m]' },
    { title: 'Validate', model: 'sonnet[1m]' },
    { title: 'Match', model: 'sonnet[1m]' },
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
          line: { type: 'string', description: 'line number IN THE CLONED SOURCE FILE (clonePath), never the position inside the .diff file' },
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

const READ_ONLY = ['Write', 'Edit', 'NotebookEdit']
const NO_CODE = [...READ_ONLY, 'Read', 'Grep', 'Glob', 'Bash']

const SOURCES = `Sources (read with Read/Grep, absolute paths):
- Manifest: ${WORK}/manifest.json — array of {repo, iid, clonePath, diffPath, source_branch, clonedBranch, state, web_url, claudeMd}.
  When clonedBranch differs from source_branch, the MR is already merged and its source branch is gone: the clone is the post-merge TARGET branch. It contains this MR's changes plus anything merged after them, so the code around the change may differ from the diff's context — trust the clone for line numbers, and the diff for what this MR actually changed.
- Diffs: ${WORK}/diffs/*.diff (one per MR).
- Full code (shallow clones): ${WORK}/repos/* — clonePath from the manifest (may be empty if the clone failed).`

const taskPrompt = `Review one Jira task spread across several merge requests (possibly in different repositories). Your review lens (role + what to hunt for) is defined by your agent prompt — stay strictly within it.

${SOURCES}
- Repo conventions: \`<clonePath>/CLAUDE.md\` when manifest's claudeMd is true — the repo's rules and DELIBERATE quirks. Read it BEFORE judging that repo.

LINE NUMBERS: the "line" field MUST be the line number in the CLONED SOURCE FILE under clonePath — NEVER the line position inside the .diff file. A unified diff shifts every hunk by the preamble above it (for a new-file hunk the added lines are offset by the diff-file line where the hunk starts), so positions read off the .diff are wrong. To pin a line: open the actual file in clonePath and read its real line number there; use the diff only to locate WHAT changed, not to count line numbers.

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

// STAGE 1 — all lenses + completeness in one parallel() (barrier: dedupe needs all findings together).
phase('Review')
const runLens = async (key) => {
  // over-engineering only: hand it the task text so requirement-justified complexity
  // isn't flagged. The task.md path is known here, not in the agent .md, so the
  // context add-on lives in the workflow. Other lenses keep the bare taskPrompt.
  let prompt = key === 'over-engineering' && KEY
    ? `${taskPrompt}\n\nContext — what the task actually required: \`${WORK}/task.md\` (its description + comments). Complexity that this requirement genuinely demands is NOT over-engineering; only flag complexity beyond what the task asks for.`
    : taskPrompt
  const opts = { label: `lens:${key}`, phase: 'Review', schema: FINDINGS, model: 'opus[1m]', agentType: `review-${key}` }
  let r = await agent(prompt, opts)
  if (!r) r = await agent(prompt, opts) // 1 retry on a dropped stream
  return { lens: key, findings: (r && r.findings) || [] }
}

// Completeness agent (jira-only): reads task.md requirements and reports what the
// MRs left unbuilt. Same shape as runLens so it runs alongside the lenses.
const completenessPrompt = `Check whether this Jira task's MRs actually deliver what the task asked for. Your role (scope/coverage check, not defect hunting) is defined by your agent prompt.

Requirements source: \`${WORK}/task.md\` — the task's title, description, and comments. This is what was asked.
What was built (read with Read/Grep, absolute paths):
- Manifest: ${WORK}/manifest.json — array of {repo, iid, clonePath, diffPath, source_branch, clonedBranch, state, web_url, claudeMd}.
  When clonedBranch differs from source_branch, the MR is already merged and its source branch is gone: the clone is the post-merge TARGET branch. It contains this MR's changes plus anything merged after them, so the code around the change may differ from the diff's context — trust the clone for line numbers, and the diff for what this MR actually changed.
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
  const opts = { label: 'completeness', phase: 'Review', schema: FINDINGS, model: 'opus[1m]', agentType: 'review-completeness' }
  let r = await agent(completenessPrompt, opts)
  if (!r) r = await agent(completenessPrompt, opts) // 1 retry on a dropped stream
  return { lens: 'completeness', findings: (r && r.findings) || [] }
}

const reviewThunks = LENSES.map((k) => () => runLens(k))
if (KEY) reviewThunks.push(() => runCompleteness())
const lensResults = await parallel(reviewThunks)

const all = lensResults
  .filter(Boolean)
  .flatMap((r) => r.findings.map((f) => ({ ...f, lens: r.lens })))

if (all.length === 0) {
  return `# ${HEADER}\n\n✅ Чисто — линзы (${LENSES.join(', ')}) не нашли проблем в изменённом коде.`
}
all.forEach((f, i) => { f.index = i })

// STAGE 1.5 — Dedupe (cheap sonnet, no code access): different lenses routinely
// report the same defect. Merging here means one validator per real problem
// instead of one per duplicate. A null result degrades to "every finding is its
// own group" — nothing is lost, we just validate the duplicates too.
phase('Dedupe')
const CLUSTERS = {
  type: 'object',
  required: ['clusters'],
  properties: {
    clusters: {
      type: 'array',
      items: {
        type: 'object',
        required: ['indices'],
        properties: { indices: { type: 'array', items: { type: 'integer' } } },
      },
    },
  },
}
const dedupePrompt = `Group automated review findings that describe the SAME problem in the SAME place.

Findings (JSON; "index" is the stable id, "lens" is the reviewer that reported it):
${JSON.stringify(all.map((f) => ({ index: f.index, lens: f.lens, severity: f.severity, repo: f.repo, iid: f.iid, file: f.file, line: f.line, title: f.title, why: f.why })))}

You judge from this JSON only — do NOT read any code, do NOT open files.

Rules:
- Two findings belong in one cluster when they are the same underlying defect at the same place: same repo+iid, same file, and the same mechanism. Different wording, different lens, slightly different line — still one cluster.
- Different problems in the same file are NOT one cluster. Same-name problems in different repos/MRs are NOT one cluster. When unsure, leave them apart — a wrong merge silently hides a real defect.
- Findings with lens = "completeness" may only cluster with other "completeness" findings. NEVER put a completeness finding in a cluster with a code defect.
- Every index appears at most once across all clusters. Report only clusters of 2+ indices; singletons are implied and must be omitted.

No duplicates at all → return {"clusters": []}.`
const deduped = await agent(dedupePrompt, { label: 'dedupe', phase: 'Dedupe', model: 'sonnet[1m]', schema: CLUSTERS, disallowedTools: NO_CODE })

const RANK = { critical: 3, warning: 2, suggestion: 1 }
const byIndex = new Map(all.map((f) => [f.index, f]))
const groups = []
const claimed = new Set()
for (const c of (deduped && deduped.clusters) || []) {
  const members = (c.indices || [])
    .map((i) => byIndex.get(i))
    .filter((f) => f && !claimed.has(f.index))
  if (members.length < 2) continue
  // completeness never merges with code defects — drop the whole cluster if mixed
  const kinds = new Set(members.map((f) => (f.lens === 'completeness' ? 'completeness' : 'defect')))
  if (kinds.size > 1) continue
  members.forEach((f) => claimed.add(f.index))
  groups.push(members)
}
for (const f of all) if (!claimed.has(f.index)) groups.push([f])

const merged = groups.map((members) => {
  const rep = members.slice().sort((a, b) =>
    (RANK[b.severity] || 0) - (RANK[a.severity] || 0) || a.index - b.index)[0]
  return {
    ...rep,
    lenses: [...new Set(members.map((f) => f.lens))],
    variants: members.filter((f) => f.index !== rep.index).map((f) => f.why),
  }
})
log(`dedupe: ${all.length} findings -> ${merged.length} groups`)

// STAGE 1.6 — Validate: one sonnet agent per merged finding, sent into the clone
// to confirm or refute it and to pin file/line against the real source. Refuted
// findings never reach the report; "uncertain" survives carrying its doubt.
phase('Validate')
const VERDICT = {
  type: 'object',
  required: ['verdict', 'file', 'line', 'doubt'],
  properties: {
    verdict: { type: 'string', enum: ['confirmed', 'refuted', 'uncertain'] },
    file: { type: 'string', description: 'corrected path of the offending file, or the original when it was right' },
    line: { type: 'string', description: 'line number IN THE CLONED SOURCE FILE, "" if N/A' },
    doubt: { type: 'string', description: 'RUSSIAN, one sentence — what could not be settled; "" unless verdict is uncertain' },
  },
}

const defectValidatePrompt = (f) => `Validate ONE automated code-review finding: confirm it from the code, or refute it. You judge this single finding — do not look for other problems, do not review anything else.

Finding:
${JSON.stringify({ severity: f.severity, repo: f.repo, iid: f.iid, file: f.file, line: f.line, title: f.title, why: f.why, explanation: f.explanation, lenses: f.lenses })}
${f.variants.length ? `\nThe same problem as phrased by the other lenses (extra evidence, same defect):\n${f.variants.map((v) => `- ${v}`).join('\n')}\n` : ''}
${SOURCES}
- Repo conventions: \`<clonePath>/CLAUDE.md\` when manifest's claudeMd is true.

Do this:
1. LOCATE: find the MR in manifest.json, open the named file inside its clonePath and find the code the finding is about. If file/line point at the wrong place but the described code does exist among that MR's changed files, CORRECT file/line instead of refuting — a wrong address is not a wrong finding.
2. PIN THE LINE: "line" MUST be the real line number in the cloned source file. NEVER a position inside the .diff — a unified diff shifts every hunk by its preamble, so numbers read off the .diff are wrong. Open the source and read the number there.
3. REFUTE, actively: is the code actually reachable? is there a guard upstream? does the described trigger really exist? is the problem introduced by THIS diff, or pre-existing code the MR only touched nearby? Does clonePath/CLAUDE.md document this as a deliberate convention (manual DI, load-bearing typos, etc.)?

Verdict:
- "confirmed" — you found the mechanism AND the trigger in the code.
- "refuted" — it cannot happen, is guarded, is pre-existing, or contradicts a documented convention.
- "uncertain" — you could not settle it either way (code not in the clone, path unreachable, evidence inconclusive). Fill "doubt" with ONE Russian sentence naming exactly what you could not verify.

Return file/line corrected (or the originals if they were already right; line "" if N/A), and doubt "" unless the verdict is "uncertain".`

const completenessValidatePrompt = (f) => `Validate ONE coverage gap reported against a Jira task: is this requirement really missing from the MRs? This is NOT a code defect — do not ask whether anything is reachable or triggerable; the whole claim is that something is ABSENT.

Finding:
${JSON.stringify({ severity: f.severity, repo: f.repo, iid: f.iid, file: f.file, line: f.line, title: f.title, why: f.why, explanation: f.explanation })}
${f.variants.length ? `\nThe same gap as phrased in other findings:\n${f.variants.map((v) => `- ${v}`).join('\n')}\n` : ''}
What was asked: \`${WORK}/task.md\` — the task's title, description and comments.
${SOURCES}

Do this:
1. Check task.md actually asks for this. Later comments override the original description when they conflict. If task.md never required it → "refuted".
2. Search the diffs AND the cloned code for the work (Grep by symbol/endpoint/config name, not just by the file the finding names — it may have been implemented elsewhere). If it IS delivered → "refuted".
3. Still missing or clearly partial → "confirmed". Cannot tell (clone failed, requirement too vague to check) → "uncertain" with ONE Russian sentence in "doubt".

file/line: where the work belongs — corrected if the finding pointed at the wrong place, "" if N/A.`

const validateOne = async (f) => {
  const prompt = f.lens === 'completeness' ? completenessValidatePrompt(f) : defectValidatePrompt(f)
  const opts = { label: `validate:${f.repo}#${f.iid}:${f.title.slice(0, 40)}`, phase: 'Validate', model: 'sonnet[1m]', schema: VERDICT, disallowedTools: READ_ONLY }
  let v = await agent(prompt, opts)
  if (!v) v = await agent(prompt, opts) // 1 retry on a dropped stream
  if (!v) return { ...f, doubt: 'валидатор не ответил — находка не проверена' }
  if (v.verdict === 'refuted') return null
  return {
    ...f,
    file: v.file || f.file,
    line: v.line || f.line,
    doubt: v.verdict === 'uncertain' ? (v.doubt || 'валидатор не смог подтвердить находку') : null,
  }
}

const survivors = (await parallel(merged.map((f) => () => validateOne(f)))).filter(Boolean)
log(`validate: ${merged.length} in -> ${survivors.length} kept (${merged.length - survivors.length} refuted)`)

if (survivors.length === 0) {
  return `# ${HEADER}\n\n✅ Чисто — подтверждённых проблем нет.`
}

// STAGE 1.7 — Match (cheap sonnet): which findings did humans already raise in MR
// comments? One agent reads the raw discussions so opus never sees them. A null
// result (matcher died) leaves every finding's comment null — nothing is lost.
phase('Match')
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
${JSON.stringify(survivors.map((f) => ({ index: f.index, repo: f.repo, iid: f.iid, file: f.file, title: f.title, why: f.why })))}

Manifest: ${WORK}/manifest.json — each MR has a discussionsPath to its human comments. Follow your agent prompt.

Return {"verdicts": [...]} with one entry {index, covered, author, quote, resolved} per finding above.`
const matched = await agent(matchPrompt, { label: 'comment-match', phase: 'Match', model: 'sonnet[1m]', agentType: 'review-comment-match', schema: VERDICTS })
for (const f of survivors) f.comment = null
if (matched && matched.verdicts) {
  for (const v of matched.verdicts) {
    const f = survivors.find((x) => x.index === v.index)
    if (f && v.covered) f.comment = { author: v.author, quote: v.quote, resolved: v.resolved }
  }
}

// STAGE 2 — summarizer (opus): recalibrate, correct wording, format. Validation
// and dedupe already happened upstream — it does NOT drop findings.
phase('Summarize')
const summaryPrompt = `You are the lead reviewer writing the final report from findings produced by ${LENSES.length} specialized lenses on one Jira task's MRs.
Code and manifest: ${WORK}/manifest.json, ${WORK}/diffs/*, ${WORK}/repos/* (read with Read/Grep when you need to check a wording against the code).

Findings (JSON; "lenses" = which lenses reported it, already merged):
${JSON.stringify(survivors)}

Every finding here has ALREADY been validated against the code by a dedicated agent, and duplicates have ALREADY been merged. Do NOT re-validate and do NOT drop findings on the merits — each one below appears in the report. Your job is calibration and presentation.

Some findings carry \`comment = {author, quote, resolved}\` — a human already raised this in the MR comments (a lens still found it, so the code is likely NOT fixed yet). Do NOT read the raw comments yourself — trust the field. Such findings go in their OWN section "💬 Уже поднято в комментариях МР", never in the severity sections.

Some findings carry \`doubt\` (a non-empty string) — the validator could not fully confirm them. Keep them, and print the doubt as an extra line in the finding: \`- **⚠️ Не подтверждено:** <doubt>\`.

Findings with \`lens = "completeness"\` are NOT code defects — they are requirements from the task that the MRs left missing or only partially done. They go in their OWN section "📋 Покрытие задачи", never in the severity sections.

Do this:
1. RECALIBRATE severity across all findings on one scale (critical = fix before merge; warning = fix soon; suggestion = optional). The lenses judged in isolation, you see the whole picture.
2. If a finding's technical wording is wrong or confusing while the underlying issue is right, correct the wording. Check the code when in doubt.
3. Order findings inside each section by importance.

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
- **Severity:** critical | warning | suggestion
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
- Every finding from the JSON appears exactly once, in exactly one section.
- Keep each finding tight — no walls of text; one clear sentence per field.`

return await agent(summaryPrompt, { label: 'summarizer', phase: 'Summarize', model: 'opus' })
