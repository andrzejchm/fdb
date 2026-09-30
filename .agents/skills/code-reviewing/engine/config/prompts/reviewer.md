BRANCH: {{branch}}
DOMAIN: {{domain}}{{shardLine}}
TITLE: {{title}}
DESCRIPTION: {{description}}
CHANGED FILES:
{{changedFiles}}

REVIEW TARGET:
{{reviewTargetInstructions}}

REVIEW SCOPE:
{{reviewScopeInstructions}}

LESSONS:
Before starting the CLI workflow, read `.ai/lessons.md` once. Treat every lesson as a project-specific heuristic ranked alongside the canonical rules for this domain. When a finding matches a documented lesson, cite the lesson identifier as `.ai/lessons.md > <lesson heading>` inside the finding body. Lessons do not override canonical rules; they augment them.

CLI WORKFLOW:
1. Run `{{cliPath}} start --branch "{{branch}}" --domain {{domain}}{{shardFlag}}`.
2. Run `{{cliPath}} next --branch "{{branch}}" --domain {{domain}}{{shardFlag}}` whenever you need the current rule reprinted.
3. Follow the CLI rule-by-rule and use the review target guidance above before reading full files.
4. For every rule, sweep ALL files in CHANGED FILES the rule could plausibly apply to — read their scoped diffs (or required file context) before recording any verdict. Do not sample "the most relevant file" and stop: an issue count of one usually means the sweep stopped at the first hit. If no changed path or file type can structurally match the rule, treat that as structural non-applicability.
5. A rule with violations is closed in two steps: record EVERY violating instance as its own finding (one finding per file:line), then run `{{cliPath}} rule-done --branch "{{branch}}" --domain {{domain}}{{shardFlag}}` to close the rule and advance. `finding` does not advance the rule; only `rule-done`, `pass`, or `skip` advance.
6. Record each finding by writing a concise finding body to a temp file (format: one-line severity+slug header, 1-3 sentences stating what is wrong and where, then at most one "Consider: <pattern or direction>" sentence; no fix code blocks, no spec excerpts, no "Affected files" lists), then run `{{cliPath}} finding --branch "{{branch}}" --domain {{domain}}{{shardFlag}} --file <path> --line <n> --side RIGHT|LEFT --body-file "<path-to-temp-file>"`. Do not put Markdown finding bodies in shell arguments; backticks, quotes, and $() are not shell-safe. `--line` and `--side` come from the gutter of the diff line you are flagging (`R<n>` → `--line <n> --side RIGHT`, `L<n>` → `--line <n> --side LEFT`). IMPORTANT: --file MUST be a file that appears in the PR diff. The CLI will hard-block findings that target files outside the diff. If the issue is in pre-existing code that this PR depends on or exposes, anchor the finding to the changed line that introduces or calls that code, and quote the problematic pre-existing code in the finding body. Use `--severity warning` to downgrade a finding recorded under a critical rule when the concrete instance is non-blocking (most useful on the final sweep rule); omit it otherwise.
7. Record a pass with `{{cliPath}} pass --branch "{{branch}}" --domain {{domain}}{{shardFlag}} --evidence "<files or diffs read + concrete condition verified>"` only when the rule applies and a full sweep found no issue. Pass evidence MUST name the files or diffs you actually read; for critical rules the CLI rejects evidence that does not cite a changed-file path (cite the token `file-list` plus reasoning when you concluded non-applicability from paths alone). Do not use generic evidence such as "checked the diff".
8. Record a skip with `{{cliPath}} skip --branch "{{branch}}" --domain {{domain}}{{shardFlag}} --reason changed-file-scope --note "<structural path/file-type reason>"` only when file types or paths make the rule structurally impossible to apply, such as a TypeScript-cast rule when every changed file is Markdown. Do not skip because you read relevant files and found no issue; that is a pass.
9. The final rule in every domain is an open sweep: report any real issue in the scoped diffs that the earlier rules did not cover. Off-checklist issues belong there — do not silently drop them earlier in the session; note them with `notes --append` and record them during the sweep.
10. Keep going until the CLI prints `DOMAIN COMPLETE`.
11. If needed, inspect progress with `{{cliPath}} status --branch "{{branch}}" --domain {{domain}}{{shardFlag}}` or append notes with `{{cliPath}} notes --branch "{{branch}}" --domain {{domain}}{{shardFlag}} --append "<note>"`.

RETURN:
Return exactly one line: <session>: phase=<phase> critical <criticalDone>/<criticalTotal>, warning <warningDone>/<warningTotal>, passes=<n> skipped=<n> findings=<n> (matches `<cli> status --branch ... --domain ...`; copy that line).
