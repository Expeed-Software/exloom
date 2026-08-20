# App Knowledge — <APPLICATION>

What QA's corrections have taught about this application. Written only through confirmed deviation capture — see `../skills/references/deviation-learning.md`.

Every entry ends with a confidence marker and the date it was last confirmed:

- `confirmed` — corroborated by a later story or explicitly confirmed. Treat as fact.
- `seen once` — observed once. Treat as a suggestion; verify with QA before relying on it.
- `volatile` — corrected more than twice. Treat as a suggestion regardless of age.

**Never record** passwords, tokens, keys, connection strings, real customer names or emails, account numbers, or anything specific to one test account. This file may be shared or committed.

## Navigation

- <feature>: <verified path> — confirmed, <YYYY-MM-DD>

## Vocabulary

Real screen titles, field labels, and button text as they appear in the application.

- <what the model guessed> is actually <real label> — confirmed, <YYYY-MM-DD>

## Error messages

Verbatim strings. These make negative-case expected results executable instead of vague.

- <trigger>: "<exact message>" — confirmed, <YYYY-MM-DD>

## Roles

- <role name>: <what it can reach and do> — confirmed, <YYYY-MM-DD>

## Conventions

Product-level judgments that shape test design.

- <e.g. tenant isolation cases are always P0 here> — confirmed, <YYYY-MM-DD>

## Dependencies

Recurring prerequisites and downstream effects that hold across stories.

- <e.g. every order action requires an active subscription> — confirmed, <YYYY-MM-DD>
