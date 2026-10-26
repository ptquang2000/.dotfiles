# Comments policy

Do not add a comment for every edit you make. Silent, obvious, or cosmetic
changes need no commentary. Only add a comment when the why is genuinely not
obvious from the code itself.

Rules:

1. **Never narrate an edit.** Do not write comments like `// updated this line`,
   `// changed to new logic`, or `// removed <name>`. They describe the past,
   not the code, and git history already has it.
2. **Don't restate the code.** Skip comments that merely paraphrase the next
   line (`// return 0;` before `return 0;`).
3. **Keep useful comments only** when they explain intent, a workaround, a
   constraint, a link to an issue, or a non-obvious piece of domain knowledge.
4. **Don't leave marker comments** such as `<-- changed`, `<!-- existing -->`,
   or trailing `# new` annotations left next to modified lines.
5. **Removing a comment the user didn't ask about is still fine** when it is
   obsolete or contradicts the code after your edit.
