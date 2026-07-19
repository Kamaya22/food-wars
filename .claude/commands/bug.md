---
description: File a new bug ticket seeded with the bug report template
argument-hint: [short title]
---

Bug title: $ARGUMENTS

1. Determine this project's id (from `project.yml` `id:`, or `list_projects` if the MCP
   is running).
2. Read `.project-template/bug-report-template.md` to get the body skeleton.
3. Create the ticket with the local-jira `create_feature` tool: `projectId` = this
   project, `title` = the title above (ask me for one if empty), `type: "bug"`, and
   `body` = the bug template skeleton. It lands in `backlog`.
4. Tell me the new ticket id and file path, and that I should fill in Environment /
   Bug detected / Reproduction steps / Suspected causes. When it's ready, run
   `/fix <id>`.
