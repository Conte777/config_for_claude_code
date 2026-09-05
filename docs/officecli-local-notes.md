# officecli — local notes

`src/skills/officecli/` was a vendored copy of the upstream SKILL.md. It is gone: the
skill now comes from the `officecli@officecli` plugin (marketplace `officecli/officecli`),
installed by `setup.sh`.

Upstream has since replaced that SKILL.md with a short capability-check router, so the
notes below — added on top of the vendored copy in `83ccabe`, `9517c59` and `3afb8fe` —
have no upstream home any more. They are behaviour observations, not instructions; keep
them here until upstream documents them.

## batch is atomic by default (v1.0.137+) — verified live

Every item still runs and is reported, so `N succeeded, M failed` stays meaningful and
every failure surfaces. But if *any* item fails, the whole batch rolls back and the file
on disk is left byte-identical to before the batch ran. Confirmed live in both standalone
and resident mode.

- `--best-effort` restores the old apply-what-succeeds behaviour. Useful for lossy
  `dump → batch` replays, where losing everything over one unsupported item is worse
  than a partial result.
- `--stop-on-error` only changes how early the run stops (remaining items are `skipped`),
  not whether what already ran gets kept. Combine it with `--best-effort` for
  "stop at the first failure but keep what succeeded".
- `--force` is unrelated — it is only the docx-protection bypass.
- Failed items carry a machine-readable `code` field (same list as `error.code`);
  a rolled-back batch's JSON summary carries `"atomicRolledBack": true`.

## Flush only at the non-officecli boundary

officecli's own reads (`get` / `query` / `view` / `dump`) always see the latest edits, so
there is never a need to save mid-workflow. Run `save` (keeps the resident) or `close`
(flush + release) only **before a non-officecli program reads the file** — python-docx /
openpyxl, Word, a renderer, delivery or upload. Idle sessions auto-flush within seconds;
`OFFICECLI_RESIDENT_FLUSH=each` makes every mutation flush before returning.

## MCP help takes one string, not a structured object

The MCP tool has exactly one parameter, `command`, and passes it to the CLI verbatim:
`{"command": "help docx paragraph"}` — not `{"command": "help", "format": "docx", "type": "paragraph"}`.

## Selector forms that bite

- **pptx connector** `from` / `to` accept only the full-path `@name=` / `@id=` form.
  Bare `@name=Foo` is rejected; it must be `/slide[N]/shape[@name=Foo]`.
- **docx revision**: `set /revision[...]` takes the bare `@author=` / `@type=` selector,
  but `query 'revision[...]'` needs the dotted `revision.author=` / `revision.type=` form.
  `move` + `revision` works on run-level paths only, not paragraph-level.
- **docx textbox/shape** is add-mostly: `get` returns a raw XML preview with no structured
  readback, and `set` is limited to width / height / geometry / fill / `line.*`. Position is
  `anchor.x` / `anchor.y`, not bare `x` / `y`. `textDirection`, rotation, gradient and shadow
  are textbox-only — a docx shape has neither rotation nor gradient.
- **xlsx pivottable**: `labelFilter=field:type:value` and `topN=<int>` are add-time only,
  and `fillDownLabels` is an alias of `repeatLabels`, not a separate feature.
