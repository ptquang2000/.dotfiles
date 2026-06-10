---
name: handoff
description: Cross-session context migration for OpenCode work. Use when the user asks to hand off, migrate, compact, resume in a new session, or preserve the essential current-session context as a self-contained continuation prompt.
---

# Handoff

## Goal

Produce a self-contained handoff context that a fresh session can use to continue the work without relying on the old chat.

This is not a project plan and not a durable task file by default. It is a one-shot context migration summary, similar to a `/handoff` command.

## Workflow

1. Confirm there is meaningful context to migrate. If the session is empty or only conversational, say there is not enough to hand off.
2. Gather fresh evidence before summarizing:
   - Read the current conversation context available to OpenCode.
   - Run `git status --porcelain` when inside a Git worktree.
   - Run a focused recent-change command such as `git diff --stat` or `git diff --stat HEAD~10..HEAD` when appropriate.
   - Read any active plan/checklist state visible in the conversation.
3. Extract only continuation-critical facts:
   - Verbatim user requests and explicit constraints.
   - Completed work, current state, pending work, decisions, verification, risks, and key files.
4. Read `references/handoff-template.md` for the output shape.
5. Output the handoff context in chat unless the user explicitly asks to write it to a file.
6. End with short continuation instructions telling the user to start a new session and paste the handoff context.

## Do

- Make the summary self-contained.
- Preserve user requests and explicit constraints verbatim.
- Prefer workspace-relative file paths when possible.
- Include changed or important files, capped at 10.
- Include verification status and uncommitted-change status when known.
- Include only secrets-safe details; redact tokens, keys, credentials, private URLs, and personal data.
- Keep the summary focused on what matters for continuation, not every implementation detail.

## Do Not

- Do not create or spawn a new session programmatically.
- Do not invent constraints, decisions, tests, or file changes.
- Do not paraphrase text that must be verbatim.
- Do not include long logs, full diffs, or full transcripts.
- Do not use this skill as a replacement for a real implementation plan.

## Resources

- Read `references/handoff-template.md` before writing the handoff context.

## Limits

- If evidence is missing because a command is unavailable or there is no Git worktree, say so in the summary.
- If the user only asks what the skill does, explain it instead of generating a handoff.
