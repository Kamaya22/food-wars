# Science Guide — Note Templates

Templates for `Science/`. This cluster must be readable with **zero knowledge of the project's code** — it
teaches the domain, not the implementation. The only exception is `Bridge to Architecture.md`.

---

## Science/Overview.md

```markdown
---
tags: [science, overview]
---

# <Domain> — Map of This Guide

<!-- One paragraph: what field are we in, and why does this project need it? -->

## Concepts covered
- [[<Concept A>]]
- [[<Concept B>]]
- ...

Start with [[<Concept A>]] if you're new to the domain — the rest build on it.
```

---

## Science/Concepts/\<Concept Name\>.md

```markdown
---
tags: [science, concept]
---

# <Concept Name>

## First principles
<!-- The theory/math/physics from the ground up. No code. Assume an intelligent reader new to THIS concept
     but not necessarily to the field. -->

## Why it matters here
<!-- One or two sentences on why this project's domain needs this concept at all — still no implementation detail. -->

## Diagram
​```mermaid
graph TD
    <!-- conceptual diagram — states, transformations, relationships. Role-coloring optional here since this
         isn't a system diagram, but use it if the concept maps naturally onto source/process/storage/output. -->
​```

## Related concepts
- [[<Concept B>]] — <how they relate>
```

---

## Science/Worked Examples.md

```markdown
---
tags: [science, examples]
---

# Worked Examples

## Example: <short title>
<!-- Concrete numbers or a diagrammatic walkthrough. Show the calculation or reasoning step by step. -->

## Example: <short title>
...
```

---

## Science/Pitfalls.md

```markdown
---
tags: [science, pitfalls]
---

# Common Misconceptions & Pitfalls

## <Misconception>
<!-- What people new to this domain typically get wrong, and what's actually true. -->
```

---

## Science/Further Reading.md

```markdown
---
tags: [science, reading]
---

# Further Reading

- **<Title>** — <author/source> — <one line on what it covers>
```

---

## Science/Bridge to Architecture.md

The **only** note allowed to link densely into the Architecture cluster. Keeps the rest of the Science cluster
self-contained.

```markdown
---
tags: [science, bridge]
---

# How the Theory Maps to This System

<!-- One entry per concept-to-component mapping. -->

- [[<Concept>]] is implemented in [[<Component>]] — <one line on how the abstract idea shows up concretely,
  e.g. "the Nyquist criterion sets the minimum sample rate configured in the SDR frontend">
- [[<Concept>]] is implemented in [[<Component>]] — ...
```
