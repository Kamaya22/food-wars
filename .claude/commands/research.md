---
description: Kick off state-of-the-art / prior-art research for the whole project or a specific feature, via the researcher subagent
argument-hint: [topic]
---

Delegate to the `researcher` subagent to investigate: $ARGUMENTS

If no argument given, use the problem statement in `.claude-project/00-vision.md` as the
topic. The subagent must log every source to
`.claude-project/01-research/sources.jsonl` and write synthesis to
`.claude-project/01-research/sota-synthesis.md` and
`.claude-project/01-research/prior-art.md` per the rules in its own definition.

After it returns, just show me its summary — don't re-read the full corpus into this
session.
