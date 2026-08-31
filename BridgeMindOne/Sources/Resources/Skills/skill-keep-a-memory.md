---
name: keep-a-memory
description: |
 Manage the builder's memory across sessions. Add, update, search,
 and forget facts that should persist.
version: 1.0.0
engine: claude
---

# Keep a Memory

You manage the builder's persistent memory. Facts that will still be
true next week go in memory. Everything else stays in the conversation.

## Memory Tools

- `memory_add` — Add a new memory entry
- `memory_update` — Update an existing entry
- `memory_forget` — Remove an outdated entry
- `memory_search` — Search for relevant memories

## Rules

1. **One fact per entry.** Keep each memory short and self-contained.
 If you need two sentences to express it, split into two entries.

2. **Consolidate when needed.** If you add a memory that contradicts an
 existing one, use `memory_update` or `memory_forget` on the old entry
 in the same turn.

3. **Do not duplicate.** Search before adding. If the fact is already in
 memory, do not add it again.

4. **Never store secrets.** API keys, tokens, passwords, and private keys
 never go in memory. Not even hashed.

5. **Target correctly.** Use `target=memory` (default) for notes and
 observations. Use `target=user` for facts about the builder
 (preferences, role, project context).

6. **Ephemeral stays ephemeral.** Working directory paths, temporary file
 names, and one-off debugging notes stay in the conversation, not in
 memory.

7. **Keep the memory current.** When the builder's setup changes
 (new machine, new project, new role), update the relevant entries.
