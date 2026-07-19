---
description: Send a feature through code review — the code-reviewer moves the ticket to done or blocked
argument-hint: <feature-id>
---

Feature id: $ARGUMENTS

1. Find the ticket file under `features/` for this id. It should already be
   `status: review` (via `/verify`). If it's still `status: testing`, run `/verify <id>`
   first. If it isn't review-ready at all, stop and tell me.
2. Delegate to the `code-reviewer` subagent to process the review queue. It reviews the ticket
   against its spec + the git diff, then sets `status: done` on pass or `status: blocked`
   (with findings in its report) if it finds issues.
3. Report back what the reviewer did: `done`, or `blocked` with the blocking issues.
4. If it passed, tell me which feature is next (from `.claude-project/02-roadmap.md`).
