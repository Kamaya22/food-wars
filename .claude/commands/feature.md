---
description: Start or resume work on one feature. Loads ONLY that feature's context plus the router.
argument-hint: <feature-id>
---

Feature id: $ARGUMENTS

1. Find the ticket file under `features/` for this id (e.g. `features/*-<id>.md`) and read it —
   its spec (Context + Acceptance criteria) is the body. Check other features' status by
   grepping `features/*.md` for `status:`, not by opening their folders.
2. Move it to in-progress: set the ticket's frontmatter `status: in-progress` and `updated:`
   to today (edit the file — Local-jira reads it, so the board updates automatically). If the
   local-jira MCP is running you may use `start_feature` instead.
3. Working checklist → `.claude-project/03-features/<id>-*/tasks.md`; if it's the empty
   template, break the acceptance criteria into a concrete checklist there.
4. Work through the checklist, checking items off in `tasks.md` as you go.
5. When every acceptance criterion is met, set the ticket `status: testing`. Do NOT mark
   it `review` or `done` yourself.

Run `/verify <id>` to send it through IVVQ verification (then `/ship` for code review).
