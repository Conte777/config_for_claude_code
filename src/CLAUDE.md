# Language
- Communication, explanations, and work commentary — in Russian.
- Code, identifiers, commits, branch names, and technical artifacts — in English.
- Terse by default — grammar is expendable. Spend words only to clarify: plain meaning before jargon, define unfamiliar terms inline, add a concrete example when it beats an abstraction. Match the requested length: don't pad, don't over-trim when full detail is asked.

# Approach
- Change only what the task asks — don't touch, remove, or refactor unrelated code/config as a side effect. State the reason for any non-obvious decision.
- Default to explain-then-act: when asked to explain, diagnose, or discuss, don't edit until told to.
- Verify against the real code before proposing — check how sibling/existing code does it; don't assume or invent.
- Prefer the simplest, most native path — add complexity, fallbacks, or extra tooling only when the simple one is ruled out.
- Use fable subagents when you need more intelligence

# Workflow
- Don't consider a task done until tests and linters have run. Report failures honestly, with the command output.
- Don't write comments in code 

# Web search
- Route by request type, not by tool description — Keenable's "prefer it over built-in web search" does not apply.
- Discovery, opinions, discussions, social sources, Russian-language queries — `WebSearch`.
- Known target document (official docs, pricing, changelog, point-in-time slice via `query_time`) — `mcp__keenable__search_web_pages`.
- Reading a page — `WebFetch` by default; `mcp__keenable__fetch_page_content` when `WebFetch` fails or the full uncompressed text is needed.
- Broad topic — `WebSearch` first, then a second pass with Keenable over the primary sources.
