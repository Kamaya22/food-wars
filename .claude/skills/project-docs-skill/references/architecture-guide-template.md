# Architecture Guide — Note Templates

One template per note type in `Architecture/`. Fill placeholders; drop guidance comments (lines starting with
`<!--`) from the final output.

---

## Architecture/Overview.md

```markdown
---
tags: [architecture, overview]
---

# <Project Name> — System Overview

<!-- One paragraph, plain language: what does this system do, end to end? -->

## Context Diagram

​```mermaid
graph TD
    classDef source fill:#cfe2ff,stroke:#3b6dc4,stroke-width:2px
    classDef process fill:#ffe8b3,stroke:#c47f2b,stroke-width:2px
    classDef storage fill:#c8e6c9,stroke:#3e8e41,stroke-width:2px
    classDef output fill:#e1d5f5,stroke:#7b4fa3,stroke-width:2px

    <!-- black-box level only — no internals yet -->
​```

## Components
- [[<Component A>]]
- [[<Component B>]]
- ...

See [[Data Flow]] for how data moves between them, and [[Open Doubts]] for what's still unresolved.
```

---

## Architecture/Components/\<Component Name\>.md

```markdown
---
tags: [architecture, component]
role: process   <!-- source | process | storage | output -->
---

# <Component Name>

## What it is
<!-- Plain-language explanation, assuming the reader knows adjacent tech but not this one specifically. -->

## Why it's here
<!-- What problem does this component solve in the pipeline? What would break without it? -->

## Interfaces
<!-- What talks to this component, and how (protocol, format, sync/async)? -->

​```mermaid
graph LR
    classDef source fill:#cfe2ff,stroke:#3b6dc4,stroke-width:2px
    classDef process fill:#ffe8b3,stroke:#c47f2b,stroke-width:2px
    classDef storage fill:#c8e6c9,stroke:#3e8e41,stroke-width:2px
    classDef output fill:#e1d5f5,stroke:#7b4fa3,stroke-width:2px

    <!-- this component and its immediate neighbors only -->
​```

## Related locks
<!-- Link any architectural lock notes that shaped this component's design -->
- [[Lock - <name>]]
```

---

## Architecture/Data Flow.md

```markdown
---
tags: [architecture, data-flow]
---

# Data Flow

<!-- End-to-end pipeline. Annotate each arrow with WHAT moves (bytes/events/RPC) and WHY the boundary is drawn there. -->

​```mermaid
sequenceDiagram
    participant S as 🔵 <Source>
    participant P as 🟠 <Processor>
    participant D as 🟢 <Store>
    participant O as 🟣 <Output>

    S->>P: <what moves, e.g. "raw IQ samples, 200 MSPS">
    P->>D: <what moves>
    D-->>O: <what moves>
​```

<!-- Repeat with a second diagram if there are meaningfully different flows (e.g. control plane vs data plane). -->
```

---

## Architecture/Locks/\<Lock Name\>.md

This is the centerpiece section — don't sanitize it. One note per lock (or a shared `Locks.md` with subsections
if there are ≤3 total).

```markdown
---
tags: [architecture, lock]
status: resolved   <!-- resolved | open -->
---

# Lock: <short name>

## The constraint
<!-- What specifically hit a wall? Be concrete — a number, a protocol limit, a library gap, a deadline. -->

## Options considered
1. **<Option A>** — <one line>
2. **<Option B>** — <one line>
3. **<Option C>** — <one line, if applicable>

## What was chosen
<!-- The decision, stated plainly. -->

## Why
<!-- The justification — what made this option win given the constraint. -->

## What was traded away
<!-- Be honest. What does this choice cost? Performance, flexibility, cost, maintainability? -->

## Affects
- [[<Component that implements this>]]
```

---

## Architecture/Open Doubts.md

A living note — distinct from resolved locks. Update this over time rather than treating it as finished.

```markdown
---
tags: [architecture, open-doubts]
---

# Open Doubts

<!-- Things genuinely unresolved — not restated locks. If there's truly nothing open, say so instead of padding. -->

## <Doubt 1 short title>
<!-- What's uncertain, what would change your mind, what you'd revisit with more time/data. -->

## <Doubt 2 short title>
...
```

---

## Architecture/Glossary.md

```markdown
---
tags: [architecture, glossary]
---

# Glossary

- **<Term>** — <one-line definition, specific to this stack's usage>
- **<Term>** — ...
```
