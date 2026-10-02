---
name: deploy
description: Roll a service out to dev, stage or prod through its GitLab pipeline — trigger the build job, replay a deploy of the same commit, promote develop → stage → main through merge requests, cut the release tag that carries prod. Use for any request to deploy, redeploy, promote or ship a change.
allowed-tools: Monitor, Bash(git fetch:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git status:*), Bash(git remote get-url:*), Bash(glab ci:*), Bash(glab api:*), Bash(glab mr list:*), Bash(glab mr create:*)
---

# Deploy

Values: `BRANCH` = `git rev-parse --abbrev-ref HEAD`, `PROJECT` = the URL-encoded project path (`group%2Fsub%2Fproject`) derived from `git remote get-url origin`, needed only by the `glab api` calls.

`glab ci` reads the project from the remote of the working directory; `-R group/sub/project` points it at another repository instead, which is how a rollout spanning several services runs without a single `cd`. `glab api` takes no `-R` — there the encoded path goes into the URL. In a repository you are not standing in, the pipeline's own `sha` is the only evidence of what is being deployed; check it against the commit you mean to ship.

The user names "dev", "stage" or "prod" most of the time. When they name none and the task does not imply one, ask.

## The pipeline

Work moves feature branch → `develop` → `stage` → `main`, each hop through a merge request; a tag on `main` ships prod.

| Ref | Build | Deploy | Lands in |
| --- | --- | --- | --- |
| a feature branch, `develop` | `Build`, manual | `Deploy.dev-az`, automatic once `Build` passes | dev, `$K8S_NAMESPACE_DEV` |
| `stage` | `Build`, manual | `Deploy.dev-az`, automatic once `Build` passes; `Deploy.stage-az-core`, manual | dev and stage, `$K8S_NAMESPACE_STAGE` |
| tag `vX.Y.Z` on `main` | `Build`, automatic | `Deploy.prod-az-core`, manual | prod |
| `main` | none | none | nothing |

Migration repositories run flyway instead — `DEV-AZ:Migrate-main` on `develop`, `STAGE-AZ-CORE:Migrate-main` on `stage`, `PROD-AZ-CORE:Migrate-main` on the tag, all automatic, and all finish long before any service deploy does. A repository with no `Build` job is one of those: nothing to trigger there and nothing to wait for, only a status to read.

Merge request pipelines deploy nothing. `glab ci get -b <ref>` reads the branch's own push pipeline, which is the one that carries the deploy job.

Every image is tagged `<ref-slug>-<short-sha>`, and that is what identifies the running build in the cluster — the `k8s` skill checks it.

## Dev

1. `git fetch origin`, then `git log --oneline origin/BRANCH..HEAD`. Non-empty output → stop: the commit is not on the remote, so no pipeline exists for it. `BRANCH` is `main` or `stage` → stop as well and ask: `main` carries no deploy job, and `stage` belongs to [Stage](#stage).
2. The rollout includes a migration repository → `glab ci get -R <migration repo> -b develop` and read its migrate job. Failed → stop and report: the service would land on a schema that is not there. Deploying the service from a branch other than `develop` → stop and ask, because on dev the migration ships only from `develop`.
3. `glab ci get -b BRANCH` — the pipeline and its job statuses. Check its `sha` against `git rev-parse origin/BRANCH` and keep its id as `PIPELINE_ID`.
4. Act on those statuses:
   - `Build` manual → `glab ci trigger Build -b BRANCH`. `Deploy.dev-az` follows by itself; triggering it by hand here deploys the previous image.
   - `Build` already passed and the same commit should go out again → `glab ci retry Deploy.dev-az -b BRANCH`. The image is built; a second `Build` only burns a runner.
   - `Deploy.dev-az` failed → retry that job, not `Build`.
   - `Build` failed → `glab ci trace <job-id> -b BRANCH`, report the failure. Nothing deployed.
5. Wait for `Deploy.dev-az` — see [Waiting](#waiting).
6. Deploy passed → [Health check](#health-check).

## Promote

A promotion carries one long-lived branch into the next: `FROM` → `TO` is `develop` → `stage` for stage, `stage` → `main` for prod. The merge request is opened here with `glab mr create`; the `mr` skill cuts a new feature branch whenever it stands on `develop` or `stage`, so it cannot open this one.

1. `git fetch origin`, then `git log --oneline --no-merges origin/TO..origin/FROM`. Empty → nothing to promote, `TO` already holds the work; continue with the deploy. The change the user means is absent from the list → stop: it has not reached `FROM` yet, and for `develop` that means its feature merge request is still open.
2. `glab mr list --source-branch FROM --target-branch TO` — an open one is reused. Otherwise:

   ```bash
   set -a; . ~/.claude/.env; set +a
   glab mr create --source-branch FROM --target-branch TO --title "<conventional title of the promoted change>" --reviewer "$GITLAB_MR_REVIEWERS" --description-file - --yes
   ```

   The description is markdown in Russian: one line `Перенос FROM в TO: <what changes>`, then a bullet per change from step 1's list.
3. Show the merge request URL and step 1's list per repository, and merge only after the user confirms — `TO` is an environment the whole team shares.
4. Poll `glab api "projects/PROJECT/merge_requests/IID"` every 5 s until `detailed_merge_status` is `mergeable`, then `glab api -X PUT "projects/PROJECT/merge_requests/IID/merge"`. `has_conflicts` true, or no `mergeable` within a minute → stop and report the status.

## Stage

1. [Promote](#promote) `develop` → `stage` in every repository of the rollout, migration repositories included.
2. The rollout includes a migration repository → `glab ci get -R <migration repo> -b stage` and read its `STAGE-AZ-CORE:Migrate-main`. Failed → stop before any service deploy.
3. `git fetch origin`, then `glab ci get -b stage`. Its `sha` matches `git rev-parse origin/stage` → keep its id as `PIPELINE_ID`; a mismatch means the merge's pipeline has not appeared yet, so read again.
4. Act on those statuses:
   - `Build` manual → `glab ci trigger Build -b stage`. `Deploy.dev-az` follows by itself and puts the `stage` branch on dev as well.
   - `Build` failed → `glab ci trace <job-id> -b stage`, report the failure. Nothing deployed.
   - `Deploy.stage-az-core` already ran and the same commit should go out again → `glab ci retry Deploy.stage-az-core -b stage`, then straight to the wait in step 6.
5. Wait for `Build` — [Waiting](#waiting) with `DEPLOY_JOB` = `Deploy.stage-az-core` ends on `Deploy.stage-az-core=manual`.
6. `glab ci trigger Deploy.stage-az-core -b stage`, and wait again. Failed → `glab ci retry Deploy.stage-az-core -b stage`, not `Build`.
7. Deploy passed → [Health check](#health-check) on stage.

## Prod

Prod is real production: every step here ships to customers.

1. `glab ci get -b stage` per repository: its `sha` matches `git rev-parse origin/stage` and `Deploy.stage-az-core` is `success`. Otherwise stop and ask — prod would receive a commit stage never ran.
2. `glab api "projects/PROJECT/repository/tags?per_page=1"` per repository for its latest tag. Version sequences are independent, so each repository gets its own patch bump unless the user names another version.
3. [Promote](#promote) `stage` → `main`. Its confirmation carries the tag list too, as `repository: current → new` — one answer covers the merge, the tag and the prod deploy. A tag is a release the whole team sees, and deleting it does not undo the deploy it started.
4. `glab api -X POST "projects/PROJECT/repository/tags" -f tag_name=vX.Y.Z -f ref=main`, after the merge has landed.
5. The rollout includes a migration repository → read its `PROD-AZ-CORE:Migrate-main`, which the same tag starts, before triggering any service deploy. Failed → stop.
6. The tag pipeline starts building on its own. Take its id from `glab ci get -b vX.Y.Z` as `PIPELINE_ID`. Its deploy job is named anything other than `Deploy.prod-az-core` → stop and ask.
7. Wait for `Build` ([Waiting](#waiting) ends on `Deploy.prod-az-core=manual`), then `glab ci trigger Deploy.prod-az-core -b vX.Y.Z` and wait again for the deploy job.
8. No health check: `~/.claude/.env` holds no prod kubeconfig, so the `k8s` skill cannot reach prod. The report says the service was not checked.

## Waiting

One `Monitor` per repository, pinned to `PIPELINE_ID`, with this loop — `DEPLOY_JOB` is `Deploy.dev-az`, `Deploy.stage-az-core` or `Deploy.prod-az-core`, `-R` only for a repository you are not standing in:

```bash
prev=; while :; do
  cur=$(glab ci get -R REPO -p PIPELINE_ID -F json --jq '(.jobs|map({(.name):.})|add) as $j | $j.Build as $b | $j["DEPLOY_JOB"] as $d | "Build=\($b.status) DEPLOY_JOB=\($d.status) " + (if ($b.status|IN("failed","canceled")) then "END" elif $b.status=="success" and ($d.status=="manual" or $d.status=="skipped" or (($d.status|IN("success","failed","canceled")) and ($d.started_at // "") >= $b.finished_at)) then "END" else "WAIT" end)' 2>&1)
  [ "$cur" != "$prev" ] && printf '%s\n' "$cur"; prev=$cur
  case "$cur" in *' END') exit 0;; esac
  sleep 30
done
```

`timeout_ms` 1800000. Every piece of the loop answers a silent or false monitor seen in past runs:

- **Pinned pipeline.** `-b BRANCH` jumps to whatever pipeline a later push creates, which then sits on a manual `Build` forever.
- **`started_at` after Build's `finished_at`.** A deploy job does not wait for `Build`: after a retried `Build`, the pipeline still shows the stale deploy that ran against the failed one, already `failed`.
- **`--jq` inside `glab`.** The Monitor shell is zsh, whose `echo` rewrites the `\n` in commit messages and breaks the JSON; the parse error vanishes and the loop never sees a status. Loop over repositories with separate monitors, never `for r in $list` — zsh does not split the string.
- **Print on change.** A line per poll floods the session with identical notifications.

`END` is the only exit: read the last line for which job settled and how.

## Health check

A green deploy job says the manifests applied, not that the service lives. Every service repository deployed to dev or stage gets this check through the `k8s` skill, in the environment it deployed to; migration repositories have no pod and skip it. The service is `app=<last segment of the repository path>`; no pods under that label → stop and ask.

The service is **healthy** when every point holds:

1. `rollout status` of the deployment completes.
2. Every pod is Ready and runs the image tagged `<ref-slug>-<short-sha>` of the commit that shipped.
3. Every new pod has `restartCount` 0.
4. The new pods' logs since start carry no `panic`, `fatal`, `error`-level line, or failed connection to a database, broker or another service.

Run points 1–4 once the pods are Ready, then again one minute later — the minute waits in a `Monitor` or a background Bash command — covering restarts and the logs of that minute.

A failed point makes the service **unhealthy**: report it with the quoted log lines or pod state, and take no further action — no rollback, no restart.

## Done

Report per repository: the promotion merge request, the pipeline URL, the deploy job's final status, the commit that went out, for prod the tag, and the health check verdict with its evidence. A stage rollout also names the dev deploy it triggered. A job still running when the report is due is reported as running, with its URL — never as deployed.
