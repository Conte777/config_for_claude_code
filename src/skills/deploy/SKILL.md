---
name: deploy
description: Roll a service out to dev or stage through its GitLab pipeline — trigger the build job, replay a deploy of the same commit, cut the release tag that carries stage. Use for any request to deploy, redeploy or ship a change.
allowed-tools: AskUserQuestion, Monitor, Bash(git fetch:*), Bash(git rev-parse:*), Bash(git log:*), Bash(git status:*), Bash(git remote get-url:*), Bash(glab ci:*), Bash(glab api:*)
---

# Deploy

Ask every question in this skill with AskUserQuestion.

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
3. `glab ci get -b BRANCH` — the pipeline and its job statuses.
4. Act on those statuses:
   - `Build` manual → `glab ci trigger Build -b BRANCH`. `Deploy.dev-az` follows by itself; triggering it by hand here deploys the previous image.
   - `Build` already passed and the same commit should go out again → `glab ci retry Deploy.dev-az -b BRANCH`. The image is built; a second `Build` only burns a runner.
   - `Deploy.dev-az` failed → retry that job, not `Build`.
   - `Build` failed → `glab ci trace <job-id> -b BRANCH`, report the failure. Nothing deployed.
5. Wait for `Deploy.dev-az` to settle: poll `glab ci get -b BRANCH` with `Monitor` in an until-loop. Never a foreground `sleep`.

## Stage

Stage ships `main`, and `main` takes changes only through a merge request from `develop`.

1. `git fetch origin --tags`, then `git log --oneline -5 origin/main`. Show the head commit and confirm with the user that it is what should ship. Work still sitting in a merge request → stop; merging it comes first, through the `mr` skill.
2. `glab api "projects/PROJECT/repository/tags?per_page=1"` per repository for its latest tag. Version sequences are independent, so each repository gets its own patch bump unless the user names another version. Confirm once, with the whole list as `repository: current → new` — a tag is a release the whole team sees, and deleting it does not undo the deploy it started.
3. `glab api -X POST "projects/PROJECT/repository/tags" -f tag_name=vX.Y.Z -f ref=main`.
4. The tag pipeline starts building on its own. Wait for `Build` (`Monitor` over `glab ci get -b vX.Y.Z`), then `glab ci trigger Deploy.prod-az-core -b vX.Y.Z`.
5. The rollout includes a migration repository → read its `PROD-AZ-CORE:Migrate-main`, which the same tag starts, before triggering the service's deploy job. Failed → stop.
6. The tag pipeline's deploy job is named anything other than `Deploy.prod-az-core` → stop and ask. A job named `Deploy.prod` belongs to a service whose tag ships real production, not stage.

## Done

Report per repository: the pipeline URL, the deploy job's final status, the commit that went out, and for stage the tag. A job still running when the report is due is reported as running, with its URL — never as deployed.

A successful deploy job is evidence enough that the release landed — the deploy is atomic and rolls itself back. Reach for the `k8s` skill only when the job failed or its status leaves the outcome unclear.
