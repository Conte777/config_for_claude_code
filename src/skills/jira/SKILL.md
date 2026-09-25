---
name: jira
description: Read or file Jira tasks — a task with its description, comments and attached GitLab MRs, JQL search ("my tasks in progress"), creating a task, moving a task to another status. Use for anything that would otherwise be a visit to the Jira UI.
allowed-tools: Bash(curl:*), Bash(jq:*)
---

# Jira work

Jira Server 9 over its REST API. Work happens in project `CUS`; an issue key (`CUS-1234`) names its own project, and any other project is named explicitly in JQL or in the create payload.

## Connect

Bind the credentials in the same shell as every `curl` call:

```bash
set -a; . ~/.claude/.env; set +a
J="https://$JIRA_URL/rest"; A="Authorization: Bearer $JIRA_PAT"
```

`JIRA_URL` is a bare host. Either variable empty → stop, and tell the user that `~/.claude/.env` has no value for that name. A 401 means the PAT expired or was revoked; say so and stop.

## Read a task

Ask only for the fields the answer needs — a full issue is tens of kilobytes of custom fields:

```bash
curl -fsS -H "$A" "$J/api/2/issue/CUS-1234?fields=summary,status,assignee,reporter,issuetype,priority,parent,description,comment" \
  | jq '{key, summary: .fields.summary, status: .fields.status.name, type: .fields.issuetype.name,
         assignee: .fields.assignee.displayName, parent: .fields.parent.key,
         description: .fields.description,
         comments: [.fields.comment.comments[] | {author: .author.displayName, created, body}]}'
```

## Attached MRs

The Git plugin's development panel holds them; the issue itself does not:

```bash
curl -fsS -H "$A" "$J/gitplugin/1.0/issuegitdetails/issue/CUS-1234/pullRequest" \
  | jq '[(.mergeRequests.items // []), (.pullRequests.items // []) | .[]
         | {title, state, url, source: .compareBranch, target: .baseBranch}]'
```

`state` is `OPENED`, `MERGED` or `CLOSED`. An empty list means no MR is linked yet, not an error. For the diff or pipeline of one MR, take its `url` to `glab`.

## Search

JQL goes through `--data-urlencode`, never pasted into the URL:

```bash
curl -fsS -G -H "$A" "$J/api/2/search" \
  --data-urlencode 'jql=assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC' \
  --data-urlencode 'fields=summary,status,assignee' --data-urlencode 'maxResults=50' \
  | jq '{total, issues: [.issues[] | {key, summary: .fields.summary, status: .fields.status.name, assignee: .fields.assignee.displayName}]}'
```

`total` above `maxResults` → say how many were left out, or page with `startAt`.

## Create a task

1. Show the user a draft: project, type, summary, description, parent for a sub-task. Create it only after their explicit yes; any edit to the draft → show it again.
2. Defaults: project `CUS`, type `Задача`, no assignee. The assignee is set only when the user names one (`"assignee": {"name": "<login>"}`).
3. Types in `CUS`: `Задача`, `Ошибка`, `История`, `Подзадача`, `Epic`. A `Подзадача` requires `parent`. For another project or type, list them first: `$J/api/2/issue/createmeta/<PROJECT>/issuetypes`, then `.../issuetypes/<id>` for its required fields.
4. The description is Jira wiki markup, not Markdown: `h2. Heading`, `*bold*`, `{{code}}`, `{code}...{code}`, `* item`, `[text|url]`.
5. Build the payload with `jq -n --arg`, so quotes and newlines in the text survive:

```bash
jq -n --arg s "$SUMMARY" --arg d "$DESCRIPTION" \
  '{fields: {project: {key: "CUS"}, issuetype: {name: "Задача"}, summary: $s, description: $d}}' \
  | curl -fsS -X POST -H "$A" -H "Content-Type: application/json" -d @- "$J/api/2/issue" | jq -r .key
```

Report the new key as `https://$JIRA_URL/browse/<KEY>`.

## Change status

Transitions depend on the workflow and the current status, and their names say little (`Release to Dev` leads to `Ready for testing`). Match on the target status, `to.name`:

```bash
curl -fsS -H "$A" "$J/api/2/issue/CUS-1234/transitions?expand=transitions.fields" \
  | jq '[.transitions[] | {id, name, to: .to.name, required: [(.fields // {}) | to_entries[] | select(.value.required) | .key]}]'
```

- One transition leads to the status the user named → run it.
- None does → list the reachable statuses and stop. A multi-step path through intermediate statuses runs only after the user confirms it.
- A transition with `required` fields → ask the user for their values and pass them under `fields`.

```bash
curl -fsS -X POST -H "$A" -H "Content-Type: application/json" \
  -d '{"transition": {"id": "81"}}' "$J/api/2/issue/CUS-1234/transitions"
```

A 204 is success. Re-read `status` and report old → new.
