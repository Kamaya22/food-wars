# Mermaid Style Guide — Role-Based Color System

Color in diagrams is **semantic, not decorative**. Every box's color must match the `role` in its component
note's frontmatter. This lets a reader learn the color code once and then scan any diagram in the vault without
re-reading labels.

## The four roles

| Role | Meaning | Color family | Hex (fill) | Hex (stroke) |
|---|---|---|---|---|
| **Source** | Where data/signal originates (sensors, APIs, user input, RF frontend) | Blue | `#cfe2ff` | `#3b6dc4` |
| **Process** | Transformation, compute, business logic | Amber/Orange | `#ffe8b3` | `#c47f2b` |
| **Storage** | Persistence — DBs, buffers, queues, filesystems | Green | `#c8e6c9` | `#3e8e41` |
| **Output** | Sinks — UI, external delivery, actuators, exports | Purple | `#e1d5f5` | `#7b4fa3` |

These are deliberately soft/pastel fills with a saturated stroke — readable in both Obsidian's light and dark
theme, since Mermaid diagrams in Obsidian inherit the app's current theme background.

## Standard classDef block (copy-paste into every diagram)

```mermaid
graph TD
    classDef source fill:#cfe2ff,stroke:#3b6dc4,stroke-width:2px,color:#1a1a1a
    classDef process fill:#ffe8b3,stroke:#c47f2b,stroke-width:2px,color:#1a1a1a
    classDef storage fill:#c8e6c9,stroke:#3e8e41,stroke-width:2px,color:#1a1a1a
    classDef output fill:#e1d5f5,stroke:#7b4fa3,stroke-width:2px,color:#1a1a1a

    A[Signal Source]:::source --> B[Processing Stage]:::process
    B --> C[(Storage)]:::storage
    C --> D[Output / UI]:::output
```

Apply the `:::role` suffix to every node. Don't leave nodes unstyled — an unstyled node reads as "uncategorized"
which usually means the role wasn't decided, which is itself worth flagging rather than skipping.

## Sequence diagrams

`sequenceDiagram` doesn't support `classDef` on participants the same way. Use consistent **emoji or label
prefixes** instead to preserve the role signal:

```mermaid
sequenceDiagram
    participant S as 🔵 Source
    participant P as 🟠 Processor
    participant D as 🟢 Store
    participant O as 🟣 Output

    S->>P: raw data
    P->>D: write processed record
    D-->>O: query result
```

## Flowcharts with subgraphs (for grouping components by stage)

```mermaid
graph LR
    classDef source fill:#cfe2ff,stroke:#3b6dc4,stroke-width:2px
    classDef process fill:#ffe8b3,stroke:#c47f2b,stroke-width:2px
    classDef storage fill:#c8e6c9,stroke:#3e8e41,stroke-width:2px
    classDef output fill:#e1d5f5,stroke:#7b4fa3,stroke-width:2px

    subgraph Ingest
        A[Sensor]:::source
    end
    subgraph Pipeline
        B[Decode]:::process --> C[Filter]:::process
    end
    subgraph Persistence
        D[(Buffer)]:::storage
    end
    subgraph Delivery
        E[Dashboard]:::output
    end

    A --> B
    C --> D
    D --> E
```

## When to fall back to PlantUML

Only when Mermaid genuinely can't express the diagram well:
- Detailed **deployment diagrams** with `<<stereotype>>` annotations and nested nodes
- **Component diagrams** with interface lollipops/sockets
- Diagrams needing precise **multiplicities** (`1..*`, `0..1`) on associations

For PlantUML, use `skinparam` to mirror the same four-color role system:

```plantuml
@startuml
skinparam component {
  BackgroundColor<<source>> #cfe2ff
  BorderColor<<source>> #3b6dc4
  BackgroundColor<<process>> #ffe8b3
  BorderColor<<process>> #c47f2b
  BackgroundColor<<storage>> #c8e6c9
  BorderColor<<storage>> #3e8e41
  BackgroundColor<<output>> #e1d5f5
  BorderColor<<output>> #7b4fa3
}

component "Signal Source" <<source>> as A
component "Processing Stage" <<process>> as B
database "Storage" <<storage>> as C
component "Output / UI" <<output>> as D

A --> B
B --> C
C --> D
@enduml
```

State explicitly in the note when PlantUML is used instead of Mermaid, and why (e.g. "PlantUML used here for
stereotype annotations Mermaid doesn't support").

## Obsidian rendering notes

- Obsidian renders Mermaid natively in both edit-preview and reading view — no plugin required for the diagrams
  above.
- PlantUML is **not** rendered natively; it needs a community plugin (e.g. "PlantUML"). If a PlantUML diagram is
  used, say so in the note text so the user knows to install the plugin or view it externally.
- Keep one diagram per code fence — don't concatenate multiple `graph` blocks in one fence, Mermaid only renders
  the first.
