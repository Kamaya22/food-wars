---
description: Send a feature through IVVQ verification — the ivvq-engineer tests it and moves the ticket to review or blocked
argument-hint: <feature-id>
---

Feature id: $ARGUMENTS

1. Find the ticket file under `features/` for this id. If it isn't already
   `status: testing`, set it there first (it must be implementation-complete — if it
   isn't, stop and tell me).
2. Delegate to the `ivvq-engineer` subagent to process the testing queue. It writes/runs
   tests encoding each acceptance criterion, then sets `status: review` (all pass) or
   `status: blocked` (a criterion fails), and files a separate bug ticket for any
   defect outside this ticket's scope.
3. Report back what it did: `review`, or `blocked` with the failing checks, plus any
   bug tickets it filed.
4. If it passed, run `/ship <id>` to send it through code review.
