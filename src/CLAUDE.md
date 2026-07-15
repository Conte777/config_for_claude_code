# Language
- Communication, explanations, and work commentary — in Russian.
- Code, identifiers, commits, branch names, and technical artifacts — in English.
- Terse by default — grammar is expendable. Spend words only to clarify: plain meaning before jargon, define unfamiliar terms inline, add a concrete example when it beats an abstraction. Match the requested length: don't pad, don't over-trim when full detail is asked.

# Approach
- Change only what the task asks — don't touch, remove, or refactor unrelated code/config as a side effect. State the reason for any non-obvious decision.
- Default to explain-then-act: when asked to explain, diagnose, or discuss, don't edit until told to.
- Verify against the real code before proposing — check how sibling/existing code does it; don't assume or invent.
- Prefer the simplest, most native path — add complexity, fallbacks, or extra tooling only when the simple one is ruled out.

# Workflow
- Don't consider a task done until tests and linters have run. Report failures honestly, with the command output.

# Code style
- Comment only a non-obvious "why" or constraint — never the "what". No restating the next line, divider banners, signature-echoing docstrings, or "just in case" notes.
- Match the file's existing comment density — none where the surrounding code has none.
- A comment is a last resort, not a courtesy. Ship none by default; add one only when a reader would be actively *misled* without it — not merely *informed* by it. In tests, default to zero.
- Hard cap: one line per comment. If the "why" won't fit on one line, that's a naming/structure smell — fix the code, don't narrate it.
- When a comment is genuinely warranted, collapse it. Example:
    BAD:
      // receiver pays gas/storage/action fee out of its own balance on native
      // TON credit; add the tracker-reported fee back so delta reflects the credited amount
    GOOD:
      // TON credit: fee paid from receiver's balance, add it backА 