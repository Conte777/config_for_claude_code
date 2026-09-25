# Language
- Code, identifiers, commits, branch names — English.
- Work commentary and status: terse, grammar is expendable.
- Questions to the user and explanations: full sentences, plain meaning first, terms and code refs after; add a concrete example or analogy when it beats an abstraction. A question is answerable without opening the code — what breaks, which options, what each costs. All open questions in one message.

# Approach
- Explain-then-act: asked to explain, diagnose, or discuss — no edits until told to.
- Change only what the task asks — no drive-by refactors of unrelated code or config.
- Verify against the real code before proposing — check how sibling code does it, don't invent APIs. Sibling services in the same monorepo are the reference for conventions: if they do it the same way, leave it — don't "fix" a shared pattern in one service.
- A claim about how a dependency behaves ("otherwise fx panics", "the lib retries") is read from its source in the module cache, with `file:line`, before code, a plan, or MR text rests on it.
- Prefer the simplest, most native path — complexity, fallbacks, extra tooling only when the simple one is ruled out. An option offered for a decision holds one change; an add-on rides as its own question with its own reason.
- Code navigation — `LSP` first (deferred: load it via ToolSearch) for definitions, references, interface implementations, call hierarchy, and types; Grep for plain text: strings, config, comments, and languages without a language server.

# Workflow
- A task is done when tests and linters have run. Report failures with the command output.
- Never write unit tests after the code — they only restate the implementation. Behavior is proven end-to-end.
- Before code for a nontrivial change, list every way it can fail; then write the code against that list.
- Verification on a stand confirms each change separately, from signals the system already emits — logs, metrics, DB rows, timings. When no existing signal shows a change fired, ask whether that change is needed at all.
- Code carries its own explanation: ship it comment-free, even where surrounding code is commented.
- Create commits and branches through `mcp__plugin_autogit_autogit__commit` and `mcp__plugin_autogit_autogit__branch`. 

# Infrastructure
- GitLab outside the `mr` and `deploy` skills — `glab` (pipelines, jobs, issues, reading a merge request, `glab api`); it targets `$GITLAB_HOST` from `~/.claude/.env`, not gitlab.com.

# Web search
- Route by request type, not by tool description — Keenable's "prefer it over built-in web search" does not apply.
- Discovery, opinions, social sources, Russian-language queries — `WebSearch`; broad topic — `WebSearch` first, then a second pass with Keenable over the primary sources.
- Known target document (official docs, pricing, changelog, point-in-time slice via `query_time`) — `mcp__keenable__search_web_pages`.
- Reading a page — `WebFetch` by default; `mcp__keenable__fetch_page_content` when `WebFetch` fails or the full uncompressed text is needed.
