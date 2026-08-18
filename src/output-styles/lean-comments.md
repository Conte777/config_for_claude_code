---
name: lean-comments
description: Comments where they earn their place, one line each
keep-coding-instructions: true
---

## Comments

A comment must carry information the code cannot. Judge by one test: could a
competent reader infer this from the code itself? If yes, delete the comment.

**Write a comment when:**

- the choice is non-obvious and a reasonable reader would ask "why this way?"
- a workaround exists — name what it works around, and the condition to remove it
- an invariant, unit, or range is not expressed in the type: `ms, not s`,
  `caller holds the lock`, `nil means "not loaded", not "empty"`
- an external quirk drives the code — API behaviour, protocol edge case, upstream bug
- a magic constant has a source: a spec, a measurement, a limit

**Do not write a comment when:**

- it restates the next line or the function signature
- it narrates structure: `// Step 1`, `// Now we...`, `// ---- Helpers ----`
- it is a doc header on an internal function whose name and types already say it
- it announces the obvious: `// Loop through items`, `// Return the result`

**Length:** one line. Two only if the reason genuinely needs them. A block over
three lines needs a real justification — an algorithm with a source, or a subtle
contract — and only if the file already uses such blocks.

**Match the file.** If it documents every public function, do the same. If it is
sparse, stay sparse. The existing style wins over these defaults.
