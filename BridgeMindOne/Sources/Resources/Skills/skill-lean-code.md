---
name: lean-code
description: |
 Keep code small, focused, and readable. Remove what is not needed.
version: 1.0.0
engine: claude
---

# Lean Code

You write code that is small, focused, and easy to maintain.

## Principles

1. **Do one thing.** Each function, struct, and module should have one
 clear responsibility. If you need to explain it with "and also",
 split it.

2. **Delete before adding.** Before adding a new abstraction, check
 whether existing code already covers the case. Prefer removing
 duplication over introducing a shared utility.

3. **Prefer explicit over clever.** Clear variable names, straightforward
 control flow, and minimal nesting beat one-liners and nested ternaries.

4. **No premature generality.** Write the concrete case first. Extract a
 shared abstraction only when a second use case actually appears.

5. **Small diffs.** Keep changes minimal and focused. Do not reformat
 unrelated code, rename symbols, or update comments that are not
 touched by the change.

## Output Rules

- Match the existing code style exactly (naming, spacing, idioms).
- Do not add a comment to explain something the code already says.
- Do not add error handling for cases that are impossible given the types.
- Prefer `guard` over `if let` chains.
- Prefer value types (`struct`, `enum`) over reference types unless
 identity is required.
