---
name: project-docs
description: Generates an Obsidian vault (linked notes, wikilinks, folders) documenting a project built with unfamiliar stacks/technologies — a Technical Architecture Guide (diagrams, component breakdowns, architectural locks/tradeoffs, open doubts) plus a standalone Science/Domain Educational Guide (first-principles theory), with role-colored Mermaid diagrams (source/process/storage/output). Trigger on requests to document, explain, or write up an architecture/pipeline/data-flow for learning purposes, understand a stack post-hoc, or produce an educational project writeup for an Obsidian vault.
---

# Project Documentation Generator (Obsidian Vault)

Produces a **two-cluster Obsidian vault** for a project the user built (often with Claude Code) using tech they
want to actually understand, not just have working. The two clusters have different jobs and must not be merged:

1. **Technical Architecture Guide** — how *this* system is built: components, data flow, the hard tradeoffs made,
   and what's still unresolved.
2. **Science/Domain Educational Guide** — the underlying theory (RF, DSP, distributed systems, whatever domain
   applies), independent of this specific codebase.

Output is a **folder of linked Obsidian notes**, not one or two giant files — see `references/vault-structure.md`
for the folder layout, note-per-concept granularity, wikilink conventions, and frontmatter/tag scheme.

Read `references/architecture-guide-template.md` and `references/science-guide-template.md` before drafting either
cluster — they contain the full section-by-section structure, now expressed as separate linked notes rather than
single-file sections. Read `references/mermaid-style-guide.md` before writing any diagram — it has the required
color system and copy-paste `classDef` blocks (unchanged for Obsidian — its Mermaid renderer supports the same
syntax).

## Workflow

### 1. Establish scope
Before drafting, confirm with the user (skip questions whose answers are already obvious from context):
- Which project/repo — get the actual code if possible (ask them to point you at files, or use it if already
  in context). Documenting from memory/conversation alone produces a thinner, more speculative doc — say so if
  that's the situation.
- Is this a template/skill run (produce placeholder structure) or a real pass on a real project (produce filled
  content)?
- Any stack/domain specifics that change which science-guide reference file applies (see step 4).

### 2. Gather material
If a repo or files are available: read the actual code, config, and any existing README/docs before drafting.
Architectural locks and tradeoffs should come from real constraints found in the code (dependency choices,
config values, comments, commit messages) — not invented. If no code is available, draft from what's been
discussed and **flag speculative sections clearly** rather than presenting guesses as established fact.

### 3. Draft the Architecture Guide cluster
Follow `references/architecture-guide-template.md`, but emit it as **one note per component/section**, not one
big file — see `references/vault-structure.md` for exact filenames and folder placement. Key discipline:
- Every component note gets a **role tag** in its frontmatter (source / process / storage / output) that maps
  directly to the color system — this tag drives diagram coloring, so assign it deliberately, not decoratively.
- The "Architectural Locks" notes are the centerpiece the user specifically cares about — one note per lock is
  usually right if there are more than 2-3. For each: the constraint, options considered, what was chosen, what
  was traded away. Don't sanitize — the tradeoffs are the valuable part.
- "Open Doubts" is a distinct, living note — things genuinely unresolved, not restated locks. If nothing is
  genuinely open, say so rather than padding it.
- Link component notes to their diagrams and to the lock(s) that shaped them with `[[wikilinks]]` — this is
  the payoff of using a vault instead of flat files, so don't skip it.

### 4. Draft the Science Guide cluster
Follow `references/science-guide-template.md`, again as one note per concept rather than a single file. This
cluster must stand alone from the architecture cluster — someone with no access to the project's code should be
able to open the Science Guide folder and understand the domain theory. The only bridge between clusters is one
explicit note (see vault-structure.md) linking a science concept to the architecture component that implements
it — keep the cross-linking contained there, don't scatter implementation details into the theory notes.

Check if a domain-specific reference exists under `references/domains/` (e.g. `rf-dsp.md`) matching the
project's field. If one exists, use it for domain conventions and terminology. If none matches, draft the
science guide from general knowledge and note in the chat reply that no domain reference was found (don't
silently skip depth).

### 5. Diagrams
Every diagram is Mermaid by default (renders natively in most viewers). Use the color system from
`references/mermaid-style-guide.md` — role-based, not aesthetic-only:
- **Source** (data/signal origin) — blue family
- **Process** (transformation, compute) — amber/orange family
- **Storage** (persistence, buffers, DBs) — green family
- **Output** (sinks, UI, external delivery) — purple family

Fall back to PlantUML only for diagram types Mermaid handles poorly (detailed deployment/component diagrams
with stereotypes, complex multiplicities). Say explicitly when doing this and why.

### 6. Assemble and deliver
Build the vault folder exactly per `references/vault-structure.md` (two top-level folders, one per cluster, plus
a root index note with links into both). Every note needs Obsidian-style YAML frontmatter (`tags:`, `role:`
where applicable) and internal links use `[[Note Name]]` wikilink syntax, not relative markdown links.

Once the folder is built under `/home/claude/`, zip it and copy the zip to `/mnt/user-data/outputs/` so the user
gets one downloadable file they can extract straight into (or as) an Obsidian vault:
```bash
cd /home/claude && zip -r project-docs-vault.zip <vault-folder-name> && cp project-docs-vault.zip /mnt/user-data/outputs/
```
Present the zip with `present_files`. Mention in the reply that they should unzip it into (or as) their vault
so Obsidian picks up the wikilinks and graph connections.

## What this skill is not
- Not a substitute for reading real code when real code is available — always prefer grounding in the actual
  repo over general stack knowledge.
- Not a marketing/pitch document — the tone throughout is teaching and honest tradeoff analysis, including
  admitting uncertainty in the "Open Doubts" section.
