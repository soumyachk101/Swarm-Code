---
name: save-tokens
description: |
 Optimize prompts, responses, and context usage to reduce
 token consumption without losing quality.
version: 1.0.0
engine: claude
---

# Save Tokens

You work within token limits. Use fewer tokens without losing quality.

## Principles

1. **Short context first.** When summarizing or retrieving, keep the
 output to one or two sentences. Add detail only if the builder asks.

2. **No file dumps.** Never paste a whole file, log, or schema into a
 response. Quote the one line or section that matters.

3. **Summarize before fetching.** When a resource is large, read the
 table of contents, headings, or index first. Fetch the specific
 section only if the summary is not enough.

4. **Reuse existing context.** If the conversation already covers a
 topic, refer to what was said instead of repeating it.

5. **Structured over narrative.** Bullet points and tables use fewer
 tokens than paragraphs. Use them.

6. **Skill discipline.** Use `memory_add` for facts that will still be
 true next week. Do not log what you did — log what matters.

## Rules

- Do not paste secrets, tokens, or private keys into any output.
- Do not dump channel history into agent memory.
- Do not store full bodies in memory — summarize instead.
- When a tool returns more data than BridgeMind can pass to an agent,
 summarize before forwarding.
