# Handoff Context Template

Generate a plain-text continuation prompt. Do not use Markdown heading syntax.

Use this shape:

```text
HANDOFF CONTEXT
===============

USER REQUESTS AS WRITTEN
------------------------
- Paste the user's relevant requests exactly.

OBJECTIVE
---------
- State the next continuation objective in one concise sentence.

WORK COMPLETED
--------------
- Summarize what I completed in first person.
- Include important implementation or configuration choices.

CURRENT STATE
-------------
- Describe the current state of the task, workspace, and configuration.
- Include git status or say it was unavailable.

PENDING WORK
------------
- List the next concrete actions.
- Include blockers or unresolved questions.

KEY FILES
---------
- path/to/file: why it matters
- Limit to 10 files.

DECISIONS MADE
--------------
- Record decisions and short rationale.

EXPLICIT CONSTRAINTS
--------------------
- Paste only explicit constraints from the user, AGENTS.md, or other governing instructions.
- If none are known, write None.

VERIFICATION
------------
- Commands or checks run.
- Checks still needed.

RISKS AND GOTCHAS
-----------------
- Known risks, fragile assumptions, or context that could mislead the next session.

CONTINUATION PROMPT
-------------------
Continue from the handoff context above. [Add the next concrete request.]
```

Rules:

- Use bullets and short paragraphs.
- Keep it self-contained and secrets-safe.
- Prefer workspace-relative paths; use absolute paths only when they are essential.
- Include no more than 10 key files.
- Do not paste long logs, full diffs, or full conversation history.
- Keep verbatim sections verbatim.
