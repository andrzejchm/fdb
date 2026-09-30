---
name: writing-client-facing-content
description: Use when drafting, rewriting, or reviewing any message a non-technical client or external stakeholder will read — ticket comments and replies, client emails, chat or Slack messages, release and changelog notes, status or progress updates, or in-app announcements.
compatibility: opencode
metadata:
  schemaVersion: "1"
  version: "1.1.0"
  stability: stable
  category: communication
  appliesTo: any
  requires: humanizing-ai-text
---

Apply these wording, terminology, and omission rules to any message a non-technical client will read, whatever the channel.

For a page on a public docs site rather than a short message, use this project's docs-site page skill if it has one: different medium, different rules. Without such a skill, apply this one.

Assume the client only uses the product. They do not know what a PR, commit, branch, ticket status, or endpoint is.

## Contents

- Glossary Gate
- MUST
- MUST NOT
- Template Overrides
- Process
- Example

## Glossary Gate

Read the project's client glossary in full before drafting. Locate it via the project's root `AGENTS.md` routing table; `docs/GLOSSARY.md` is the conventional path.

MUST NOT draft a client-facing message without it. Terminology and language come from the glossary, never from the agent's own translation of a UI label.

If the project has no glossary, stop and tell the user this skill needs one before it can run. A usable glossary declares:

- **Client language** — the language the product UI and all client messages are written in.
- **Product terms** — the exact wording of each domain concept as it appears in the app UI, in the client language.
- **Jargon table** — internal engineering term mapped to plain client wording, or marked "omit".

Offer to draft the glossary from the app's UI strings, then resume.

## MUST

- Write in the client language declared by the glossary. Do not mix in English product terms the UI does not use.
- Use the glossary's exact product terms, matching the app UI.
- Keep it short: one or two sentences per point.
- State the outcome first: done, not yet, or needs a decision from the client.
- Describe changes in terms of what the client sees or does in the app, not how it was built.
- Give enough context that the message stands alone without the client re-reading their original report.
- Say plainly when something is not fixed or not done. Never imply progress that hasn't happened.
- Cut greetings, thanks, unsupported hedging, em dashes, and sign-offs from the draft before showing it, unless the calling workflow's fixed template explicitly requires one (see Template Overrides). Load `humanizing-ai-text` and apply it in full: em dashes are zero-tolerance by default, no sycophantic openings, no chatbot sign-offs.

## MUST NOT

- MUST NOT mention PR numbers, commit hashes, branch names, worktrees, or code file/component names.
- MUST NOT mention ticket IDs or internal statuses (`ready to test`, `merged`, `in progress`, `to do`) in prose.
- MUST NOT name who worked on it, the team, or sprint/planning details.
- MUST NOT use any term the glossary's jargon table maps away or marks "omit" — endpoint, API, migration, schema, refactor, feature flag, worker, job, queue, presigned URL, SQL, query, index, TTL, correlation id, and the rest of that table.
- MUST NOT thank the client for reporting the issue.
- MUST NOT promise a timeline the team has not committed to.
- MUST NOT open with a greeting or close with a sign-off, unless the calling workflow's fixed template explicitly requires one (see Template Overrides).

## Template Overrides

A calling workflow may define a fixed output template with its own house style — a release changelog that opens with a casual greeting and uses an em dash as its bold-name separator by design, for example.

Such a template overrides presentation defaults only: the greeting/sign-off rule and separator punctuation. It MUST NOT override anything else above, including truthfulness (state the outcome accurately, never imply progress that hasn't happened), glossary terminology, user-visible framing, and every other MUST NOT.

With no explicit template in play, default to no greeting, no sign-off, no em dash.

## Process

1. Read the project glossary, jargon table included. If it is missing, stop (see Glossary Gate).
2. Identify what the client actually asked, reported, or needs to know.
3. Draft using the MUST and MUST NOT rules above.
4. Load `humanizing-ai-text` and run its Final Scan Process on the draft.
5. Re-check against MUST NOT before sending.

Delivery and approval belong to the calling channel, not this skill — a ticket tool's write-approval gate, or an explicit approval step in a release-changelog or weekly-summary workflow. Draft here, get approval there, then post.

## Example

Shown in English for illustration. Write the real message in the client language the glossary declares.

**Wrong:** "Hi! Thanks for reporting this. PR #719 fixed the zero-truncation bug in the CoordinateInput component, it's on ready to test now. Let us know if it works!"

**Right:** "Fixed. Decimal places in a coordinate correction stay consistent now and trailing zeros are no longer cut. Please check it again."
