---
name: deploy
description: Roll a service out to dev or stage through its GitLab pipeline — trigger the build job, replay a deploy of the same commit, cut the release tag that carries stage. Use for any request to deploy, redeploy or ship a change.
allowed-tools: Monitor, Bash(git fetch:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git status:*), Bash(git remote get-url:*), Bash(glab ci:*), Bash(glab api:*)
---

# Deploy

Values: `BRANCH` = `git rev-parse --abbrev-ref HEAD`, `PROJECT` = the URL-encoded project path (`group%2Fsub%2Fproject`) derived from `git remote get-url origin`, needed only by the `glab api` calls.

`glab ci` reads the project from the remote of the working directory; `-R group/sub/project` points it at another repository instead, which is how a rollout spanning several services runs without a single `cd`. `glab api` takes no `-R` — there the encoded path goes into the URL. In a repository you are not standing in, the pipeline's own `sha` is the only evidence of what is being deployed; check it against the commit you mean to ship.

The user says only "dev" or "stage" most of the time. When they say neither and the task does not imply one, ask.

## The pipeline

| Ref | Build | Deploy | Lands in |
| --- | --- | --- | --- |
| any branch but `main` | `Build`, manual | `Deploy.dev-az`, automatic once `Build` passes | the dev namespace, `$K8S_NAMESPACE_DEV` |
| tag `vX.Y.Z` on `main` | `Build`, automatic | `Deploy.prod-az-core`, manual | the stage namespace, `$K8S_NAMESPACE_STAGE` |

Migration repositories run flyway instead — `DEV-AZ:Migrate-main` on `develop`, `PROD-AZ-CORE:Migrate-main` on the tag, both automatic, and both finish long before any service deploy does. A repository with no `Build` job is one of those: nothing to trigger there and nothing to wait for, only a status to read.

Merge request pipelines deploy nothing. `glab ci get -b <ref>` reads the branch's own push pipeline, which is the one that carries the deploy job.

Every image is tagged `<ref-slug>-<short-sha>`, and that is what identifies the running build in the cluster — the `k8s` skill checks it.

## Dev

1. `git fetch origin`, then `git log --oneline origin/BRANCH..HEAD`. Non-empty output → stop: the commit is not on the remote, so no pipeline exists for it. `BRANCH` is `main` → stop as well; the dev deploy job never runs there.
2. The rollout includes a migration repository → `glab ci get -R <migration repo> -b develop` and read its migrate job. Failed → stop and report: the service would land on a schema that is not there. Deploying the service from a branch other than `develop` → stop and ask, because on dev the migration ships only from `develop`.
3. `glab ci get -b BRANCH` — the pipeline and its job statuses. Check its `sha` against `git rev-parse origin/BRANCH` and keep its id as `PIPELINE_ID`.
4. Act on those statuses:
   - `Build` manual → `glab ci trigger Build -b BRANCH`. `Deploy.dev-az` follows by itself; triggering it by hand here deploys the previous image.
   - `Build` already passed and the same commit should go out again → `glab ci retry Deploy.dev-az -b BRANCH`. The image is built; a second `Build` only burns a runner.
   - `Deploy.dev-az` failed → retry that job, not `Build`.
   - `Build` failed → `glab ci trace <job-id> -b BRANCH`, report the failure. Nothing deployed.
5. Wait for `Deploy.dev-az` — see [Waiting](#waiting).
6. Deploy passed → [Health check](#health-check).

## Stage

Stage ships `main`, and `main` takes changes only through a merge request from `develop`.

1. `git fetch origin --tags`, then `git log --oneline -5 origin/main`. Show the head commit and confirm with the user that it is what should ship. Work still sitting in a merge request → stop; merging it comes first, through the `mr` skill.
2. `glab api "projects/PROJECT/repository/tags?per_page=1"` per repository for its latest tag. Version sequences are independent, so each repository gets its own patch bump unless the user names another version. Confirm once, with the whole list as `repository: current → new` — a tag is a release the whole team sees, and deleting it does not undo the deploy it started.
3. `glab api -X POST "projects/PROJECT/repository/tags" -f tag_name=vX.Y.Z -f ref=main`.
4. The tag pipeline starts building on its own. Take its id from `glab ci get -b vX.Y.Z` as `PIPELINE_ID`, wait for `Build` ([Waiting](#waiting) ends on `Deploy.prod-az-core=manual`), then `glab ci trigger Deploy.prod-az-core -b vX.Y.Z` and wait again for the deploy job.
5. The rollout includes a migration repository → read its `PROD-AZ-CORE:Migrate-main`, which the same tag starts, before triggering the service's deploy job. Failed → stop.
6. The tag pipeline's deploy job is named anything other than `Deploy.prod-az-core` → stop and ask. A job named `Deploy.prod` belongs to a service whose tag ships real production, not stage.
7. Deploy passed → [Health check](#health-check).

## Waiting

One `Monitor` per repository, pinned to `PIPELINE_ID`, with this loop — `DEPLOY_JOB` is `Deploy.dev-az` or `Deploy.prod-az-core`, `-R` only for a repository you are not standing in:

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

A green deploy job says the manifests applied, not that the service lives. Every service repository gets this check through the `k8s` skill, in the environment it deployed to; migration repositories have no pod and skip it. The service is `app=<last segment of the repository path>`; no pods under that label → stop and ask.

The service is **healthy** when every point holds:

1. `rollout status` of the deployment completes.
2. Every pod is Ready and runs the image tagged `<ref-slug>-<short-sha>` of the commit that shipped.
3. Every new pod has `restartCount` 0.
4. The new pods' logs since start carry no `panic`, `fatal`, `error`-level line, or failed connection to a database, broker or another service.

Run points 1–4 once the pods are Ready, then again one minute later — the minute waits in a `Monitor` or a background Bash command — covering restarts and the logs of that minute.

A failed point makes the service **unhealthy**: report it with the quoted log lines or pod state, and take no further action — no rollback, no restart.

## Done

Report per repository: the pipeline URL, the deploy job's final status, the commit that went out, for stage the tag, and the health check verdict with its evidence. A job still running when the report is due is reported as running, with its URL — never as deployed.
