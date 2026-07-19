---
description: Turn completed research into a roadmap and per-feature specs, via the spec-writer subagent
---

Delegate to the `spec-writer` subagent to produce `.claude-project/02-roadmap.md` and
per-feature spec folders under `.claude-project/03-features/`, based on
`.claude-project/00-vision.md` and the research corpus.

Refuse to proceed if `.claude-project/01-research/sota-synthesis.md` is still the empty
template — tell me to run `/research` first.

After it returns, show me just the roadmap table and the list of feature folders
created, not the full specs.
