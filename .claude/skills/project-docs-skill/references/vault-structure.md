# Vault Structure

How the output folder is organized. This is not optional scaffolding — Obsidian's value (graph view, backlinks,
quick navigation) only shows up if notes are split and linked properly, so don't collapse this back into two
big files.

## Folder layout

```
<project-name>-docs/
├── Home.md                              ← root index, links into both clusters
├── Architecture/
│   ├── Overview.md                      ← system context + top-level diagram
│   ├── Components/
│   │   ├── <Component A>.md             ← one note per component
│   │   ├── <Component B>.md
│   │   └── ...
│   ├── Data Flow.md                     ← end-to-end pipeline diagram(s)
│   ├── Locks/
│   │   ├── <Lock 1 short name>.md       ← one note per architectural lock
│   │   ├── <Lock 2 short name>.md
│   │   └── ...
│   ├── Open Doubts.md                   ← single living note, not split
│   └── Glossary.md
└── Science/
    ├── Overview.md                      ← domain map / table of contents
    ├── Concepts/
    │   ├── <Concept A>.md               ← one note per theory concept
    │   ├── <Concept B>.md
    │   └── ...
    ├── Worked Examples.md
    ├── Pitfalls.md
    ├── Further Reading.md
    └── Bridge to Architecture.md        ← the ONLY note allowed to link both clusters densely
```

Replace `<project-name>`, `<Component X>`, `<Concept X>`, `<Lock N>` with real names once scope is known. In
template/placeholder mode, keep these bracketed as literal placeholders so the user sees where to fill in.

## Note-per-concept granularity

- One component = one note. Don't bundle two components into one file even if they're small — Obsidian's
  backlink panel is what makes tradeoffs discoverable later, and that only works at note granularity.
- One architectural lock = one note **if there are more than ~3 locks**. For 1-3 locks, a single `Locks.md` note
  with subsections is fine — don't over-fragment trivial content.
- Science concepts follow the same rule: one note per concept that could plausibly be linked from multiple
  places (e.g. "Nyquist Sampling" might be referenced by three different components).

## Frontmatter scheme

Every note opens with YAML frontmatter:

```yaml
---
tags: [architecture, component]
role: process        # only on Architecture/Components/ notes — source | process | storage | output
status: resolved      # only on Locks/ notes — resolved | open
---
```

`role` is what the diagram-coloring step reads to assign colors consistently — see
`references/mermaid-style-guide.md`. Don't skip it on component notes.

## Wikilink conventions

- Use `[[Note Name]]` for links, `[[Note Name|display text]]` when the link text needs to differ from the title.
- Link a component note to the lock(s) that shaped it: `Built this way because of [[Lock - USRP Bandwidth Cap]]`.
- Link a science concept note to its implementation from the **science side**, in `Bridge to Architecture.md`
  only — e.g. `[[Nyquist Sampling]] is implemented in [[SDR Frontend]]`. Don't scatter these links into the
  theory notes themselves; it breaks the "stands alone" property the science guide needs.
- `Home.md` links to both `Architecture/Overview.md` and `Science/Overview.md`, plus directly to
  `Architecture/Locks/` entries and `Architecture/Open Doubts.md` since those are usually what the user opens
  first.

## Home.md template

```markdown
---
tags: [index]
---

# <Project Name> — Documentation

## Architecture
- [[Architecture/Overview|System Overview]]
- [[Architecture/Data Flow|Data Flow]]
- Locks: [[Lock - <name>]], [[Lock - <name>]], ...
- [[Architecture/Open Doubts|Open Doubts]]
- [[Architecture/Glossary|Glossary]]

## Science / Domain Guide
- [[Science/Overview|Domain Map]]
- Concepts: [[<Concept>]], [[<Concept>]], ...
- [[Science/Worked Examples|Worked Examples]]
- [[Science/Bridge to Architecture|How the Theory Maps to This System]]
```
