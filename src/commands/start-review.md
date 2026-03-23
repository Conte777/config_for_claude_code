---
description: Run code review on changes or entire project
argument-hint: [--all | --branch[=<base>]]
---

Your task: perform a verified code review.

## Step 1: Determine scope

If $ARGUMENTS contains both "--all" and "--branch":
  Error: "Флаги --all и --branch взаимоисключающие. Используйте один из них." → stop execution.

If $ARGUMENTS contains "--all":
  Scope: entire project

Else if $ARGUMENTS contains "--branch":
  Scope: branch changes
  If $ARGUMENTS contains "--branch=" followed by a value (e.g. "--branch=develop"):
    BASE_BRANCH = the specified value
  Else:
    Auto-detect base branch by running:
    ```bash
    git rev-parse --verify origin/main >/dev/null 2>&1 && echo "main" || \
    (git rev-parse --verify origin/master >/dev/null 2>&1 && echo "master" || \
    (git rev-parse --verify origin/develop >/dev/null 2>&1 && echo "develop" || echo "NONE"))
    ```
    If result is "NONE": Error: "Не удалось определить base branch. Укажите явно: --branch=<name>" → stop execution.
    Else: BASE_BRANCH = result

Else:
  Scope: current changes only (staged + unstaged diff)

## Step 2: Collect and group files

Collect the list of files to review based on scope:

**If scope is "entire project":**
- Find all `.go`, `.java`, `.py` files in the project
- Exclude: `vendor/`, `node_modules/`, `.git/`, `testdata/`, `*_test.go`, `*_mock.go`, generated files

**If scope is "current changes only":**
- Run `git diff --name-only` and `git diff --name-only --staged`
- Filter to supported extensions: `.go`, `.java`, `.py`

**If scope is "branch changes":**
- Run `git diff --name-only $(git merge-base HEAD origin/{BASE_BRANCH})..HEAD`
- Filter to supported extensions: `.go`, `.java`, `.py`
- If no files found: report "Нет изменений относительно ветки {BASE_BRANCH}" and stop

Then evaluate parallelization:

**≤ 10 files → single agent** (proceed to Step 3, single mode)

**> 10 files → group for parallel agents:**

1. **By Go modules**: each directory containing `go.mod` forms a separate group
2. **By language**: Go, Java, Python files go into separate groups
3. **By top-level directories**: if any group still has > 15 files, split by top-level subdirectories within that group

Constraints:
- Minimum 2 groups required for parallel mode (otherwise use single)
- Maximum **4 agents** — if more groups exist, merge the smallest ones
- Result: decision `single` or `parallel` + list of groups with their files

## Step 3: Run code review

**Single agent mode:**
Run one code review using @"code-reviewer (agent)" with the full scope description.
If scope is "branch changes", include in the prompt: `Контекст: ревью ветки "{current_branch}" относительно "{BASE_BRANCH}".`

**Parallel agent mode:**
For each group, launch a separate @"code-reviewer (agent)" with a prompt:

If scope is "branch changes":
```
Проведи code review следующих файлов ({group description: language, module, directory}).
Контекст: ревью ветки "{current_branch}" относительно "{BASE_BRANCH}".
Файлы:
- path/to/file1.go
- path/to/file2.go
...
Анализируй ТОЛЬКО перечисленные файлы.
```

Otherwise:
```
Проведи code review следующих файлов ({group description: language, module, directory}):
- path/to/file1.go
- path/to/file2.go
...
Анализируй ТОЛЬКО перечисленные файлы.
```

IMPORTANT: launch ALL agent calls in a **single message** so they run in parallel.

## Step 4: Aggregate results (parallel mode only)

Skip this step if single agent mode was used.

After all parallel agents complete:
- Collect reports from every agent
- Merge all findings into a single report following the `review-report-template.md` format
- Deduplicate findings by key `file:line`
- Recalculate the summary table (Critical / High / Low counts)
- Sum up the total number of analyzed files across all agents

## Step 5: Verify the report

After receiving the report (from single agent or after aggregation), verify every reported issue:
- Read the relevant code at the reported location
- Confirm the issue actually exists in the current codebase
- Remove false positives (issues that don't actually exist)
- Keep pre-existing issues (real problems that existed before current changes)

## Step 6: Output

Output the verified report containing only confirmed issues.
Do not include issues that don't exist in the codebase.
Pre-existing issues must be included and marked accordingly.
