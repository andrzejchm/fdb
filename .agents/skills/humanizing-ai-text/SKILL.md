---
name: humanizing-ai-text
description: Use when writing code review findings or comments, PR titles or descriptions, docs, internal chat messages, client messages, email, release or changelog text, or any other prose delivered to a human that must read like a direct human teammate wrote it. Removes AI writing patterns from text.
compatibility: opencode
metadata:
  schemaVersion: "1"
  version: "2.1.0"
  stability: stable
  category: workflow
  appliesTo: any
---

Rewrite prose so it sounds like a direct human teammate without changing what it says.

## Contents

- Core Rules
- Patterns to Eliminate
- Engineering Examples
- Adding Voice
- Output Behavior
- Final Scan Process

## Core Rules

- Keep every factual and technical claim. Shorten or restructure without changing meaning.
- Never add a fact, name, number, date, quote, citation, cause, or conclusion that the source does not support.
- Match a provided writing sample's tone, vocabulary, sentence rhythm, and level of formality.
- State the problem directly and include enough context to make the text useful.
- Keep uncertainty when the evidence, intent, or outcome is genuinely uncertain.
- Add personality only when the audience and format call for it. Keep technical, factual, legal, and security text neutral.
- Treat the patterns below as signals, not proof. Rewrite awkward combinations instead of mechanically replacing isolated words.
- Prefer the shortest complete explanation. Do not reduce useful reasoning to a cryptic fragment.

## Patterns to Eliminate

### Sycophantic Openings and Chatbot Artifacts

Delete empty praise, greetings, offers, and sign-offs:

- "Great question!"
- "Excellent point!"
- "You're absolutely right!"
- "Good catch!"
- "Nice work on this PR!"
- "Of course!" / "Certainly!"
- "I hope this helps!"
- "Let me know if you have questions!"
- "Feel free to reach out!"
- "Happy to help!"

Keep a greeting or sign-off only when the requested format calls for one.

### Unsupported Hedging

Remove qualifiers that only soften a supported claim. Keep qualifiers that carry real uncertainty.

**Before:** "You might want to consider adding validation here."
**After:** "Add validation here."

**Before:** "Because `items[0]` may be missing, this could potentially cause issues."
**After:** "`items[0]` is undefined for an empty array."

**Valid uncertainty:** "Not sure if this is intentional, but retries now skip rate-limit errors."

### Mechanical AI Vocabulary

Prefer simple words when meaning stays the same:

- Additionally/Moreover/Furthermore -> Also / And
- Utilize/Leverage -> Use
- Serves as -> Is
- In order to -> To
- Due to the fact that -> Because
- At this point in time -> Now

Watch for clusters of inflated words such as "pivotal," "seamless," "robust," "comprehensive," "landscape," and "paradigm." Do not replace a technical term mechanically. Words such as "ensure," "robust," and "key" may be precise in context.

### Forced Structure

- Break forced groups of three, not every natural list with three items.
- Merge repetitive sentence openings when they create a mechanical rhythm.
- Remove repeated dramatic fragments and unnecessary punchlines.
- State the positive claim directly instead of using "not just X, but Y."

**Before:** "This improves readability, maintainability, and scalability."
**After:** "This is easier to read and change."

**Before:** "It's not just a bug fix, it's a complete refactor."
**After:** "This refactors the whole module."

### Inflated or Unsupported Claims

Delete inflated significance, generic conclusions, and unsupported attribution.

**Before:** "This serves as a testament to the team's commitment to code quality."
**After:** Delete entirely.

**Before:** "Best practices suggest adding validation."
**After:** "Add validation."

**Before:** "This will ensure a better user experience going forward."
**After:** State the concrete effect or delete the sentence.

Never invent a source to repair a vague attribution.

### Announcements and Fake Candor

Delete staged transitions and state the point:

- "Let's dive in."
- "Here's what you need to know."
- "Honestly?"
- "Here's the thing."
- "The real question is..."

Remove objections and rejected alternatives that nobody raised. Keep them when they explain a real constraint or answer a named concern.

### Formatting Artifacts

- Do not generate em dashes (`—`) or en dashes (`–`). Rewrite with commas, periods, colons, or parentheses.
- Preserve punctuation inside quotations, source text, and explicit fixed templates. A caller may override only the formatting token its template defines.
- Avoid decorative emojis, excessive bold text, and vertical lists of bold mini-headings unless the requested format needs them.
- Punctuation or formatting alone is not proof of AI writing. Look for multiple patterns working together.

### Hidden Actors and Stale Documentation

- Prefer active voice when it clarifies who acts. Do not invent an actor the source does not name.
- Describe current behavior. Mention old behavior only in changelogs, release notes, migration guides, or text specifically about the change.
- Keep the impact and required action in review comments when they are not obvious from the finding.

## Engineering Examples

### Bug

**AI:** "I noticed that this function doesn't handle the case where the input array might be empty. This could potentially lead to unexpected behavior or errors downstream. Consider adding a check at the beginning of the function to handle this edge case gracefully."

**Human:** "Empty arrays are unhandled and can fail downstream. Add an explicit empty-input case."

### Security

**AI:** "Great progress on this feature! One thing to consider, the user input here isn't being sanitized before being used in the SQL query. This could potentially expose the application to SQL injection attacks. I'd recommend using parameterized queries to mitigate this risk."

**Human:** "This query allows SQL injection. Use parameterized values."

### Performance

**AI:** "This approach will work, but it might be worth considering the performance implications. The nested loops here result in O(n^2) complexity, which could become problematic as the dataset grows. Perhaps we could explore using a hash map to reduce this to O(n)?"

**Human:** "The nested loops make this O(n^2). Index the values in a map to make the lookup O(n)."

### Missing Error Handling

**AI:** "I see that we're making an API call here, but there doesn't appear to be error handling for cases where the request might fail. It would be beneficial to wrap this in a try-catch block to ensure we handle potential network errors gracefully and provide appropriate feedback to the user."

**Human:** "Failed requests are unhandled, so users get no error state. Handle the failure and show an error."

## Adding Voice

Use voice when the format allows it:

- **Have opinions:** "I'd go with option A. It's simpler."
- **Vary rhythm:** Mix short sentences with longer ones when the detail earns the space.
- **Keep real uncertainty:** "Not sure if intentional, but..."
- **Be specific:** Replace "concerning" with the concrete risk.

Do not add opinions, humor, first-person language, or emotional reactions to neutral reference material.

## Output Behavior

- **Embedded use:** Return only the final text required by the calling workflow.
- **File editing:** Change prose only. Preserve code blocks, metadata, data, quotations, and link targets unless the task explicitly includes them.
- **Direct rewrite:** Return the final rewrite. Explain the edits only when the user asks.

## Final Scan Process

1. Scan for combinations of the patterns above.
2. Rewrite complete sentences or paragraphs instead of patching watched words one at a time.
3. Compare source and result. Restore any lost claim and remove every unsupported addition.
4. Check that tone and personality fit the audience and format.
5. Search generated prose for `—` and `–`; remove each one unless an explicit template requires it.
6. Read the result aloud. If it still sounds staged or mechanical, rewrite around the main point.

## Reference

Adapted from [blader/humanizer](https://github.com/blader/humanizer) and [Wikipedia: Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing).
