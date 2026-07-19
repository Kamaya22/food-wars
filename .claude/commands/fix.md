---
description: Fix a bug ticket — the bug-fixer reproduces, fixes, and moves it to testing
argument-hint: <bug-id>
---

Bug id: $ARGUMENTS

1. Find the `type: bug` ticket file under `features/` for this id. If it isn't a bug,
   stop and tell me.
2. Delegate to the `bug-fixer` subagent. It reproduces with a failing regression test,
   fixes the implementation, and sets `status: testing`.
3. Report back the root cause, the fix, the regression test added, and confirm the
   ticket is now in `testing`.
4. Run `/verify <id>` to send the fix through IVVQ verification.
