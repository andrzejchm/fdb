# Verifying Prior Findings

Adjudicate every surviving prior review comment on a PR re-review: confirm claimed fixes landed, and judge whether each WONTFIX rationale is sound. Run as a subagent in parallel with the domain subagents, PR mode only. Unlike the domain reviewers, this verifier MUST read source code.

## Contents

- Scope
- Steps
- Verdicts
- GitHub actions per verdict
- Returning the result

## Scope

- In scope: surviving **unresolved** review comments authored by a bot actor (login ending in `[bot]`).
- Out of scope: deleted comments. A fixed finding's comment is deleted and its change lands in the incremental diff, so the domain reviewers re-review it. Do not reconstruct deleted comments.
- A thread marked "resolved" on GitHub is not evidence of a fix. Read the code.
- Read only the unresolved threads, the referenced file regions, and each reply rationale. Do not run a full review; new issues are the domain reviewers' job.
- Always pass `--paginate` when fetching comments and reviews. The default page size is 30 and multi-round PRs exceed it.

## Steps

1. Fetch unresolved threads and their comments:
   ```bash
   gh api graphql -f query='query($threadsCursor: String) { repository(owner: "<owner>", name: "<repo>") { pullRequest(number: <number>) { reviewThreads(first: 50, after: $threadsCursor) { nodes { id isResolved comments(first: 50) { nodes { id body author { login } path line } } } pageInfo { hasNextPage endCursor } } } } }' -F threadsCursor=null
   ```
2. Keep threads where `isResolved == false` and the first comment's author is a bot actor.
3. For each surviving comment:
   - Read the referenced file at HEAD around the referenced line.
   - Read any non-bot reply on the thread (the WONTFIX rationale, if present).
   - Assign a verdict (below) and take its GitHub action.
4. Count blocking criticals and return the result (below).

## Verdicts

| Verdict | Condition | Gate impact |
|---|---|---|
| `resolved-in-code` | The issue is no longer present in the current code (fixed or refactored away). | clears |
| `wontfix-valid` | Issue still present, but a reply gives a sound rationale: false positive, compile-time invariant, or genuinely out of this PR's scope. | clears |
| `wontfix-invalid` | Issue still present; rationale is missing, vague ("won't fix" / "by design" with no reasoning), or does not address the concern. | critical blocks |
| `still-open` | Issue still present; no reply at all. | critical blocks |

Judge soundness by reading the code, not the rationale's tone. A rationale is valid only when it correctly explains why the flagged code is safe or out of scope. When the rationale is ambiguous and the finding is critical, choose `wontfix-invalid`: fail safe and keep it blocking.

## GitHub actions per verdict

- `resolved-in-code`: resolve the thread. Optionally delete the bot comment to reduce noise.
- `wontfix-valid`: resolve the thread.
- `wontfix-invalid`: reply explaining why the rationale was rejected; leave the thread unresolved.
- `still-open`: leave the thread unresolved. The original comment stands; do not post a duplicate.

## Returning the result

A **blocking critical** is any `wontfix-invalid` or `still-open` verdict at critical severity. Return to the orchestrator:

```
VERIFIED: <n> comments — <a> resolved-in-code, <b> wontfix-valid, <c> wontfix-invalid, <d> still-open
BLOCKING CRITICALS: <count>
```

The orchestrator passes `<count>` to `review-cli compile --carried-criticals <count>`, which keeps the review `REQUEST_CHANGES` even when this round found no new criticals. It also drops any domain finding that duplicates a `resolved-in-code` or `wontfix-valid` comment.
