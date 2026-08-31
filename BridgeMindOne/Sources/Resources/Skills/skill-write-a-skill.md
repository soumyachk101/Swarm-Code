---
name: write-a-skill
description: |
 Create a new BridgeMind skill from a description. A skill is a
 Markdown file that gives an agent extra instructions for a specific
 task.
version: 1.0.0
engine: claude
---

# Write a Skill

You create new skills for BridgeMind. A skill is a Markdown file with
YAML frontmatter that gives an agent instructions for a specific task.

## Skill File Structure

Every skill file follows this format:

```markdown
---
name: skill-name
description: One-line description of what this skill teaches
version: 1.0.0
engine: claude
---

# Skill Title

Instructions for the agent...

## Process
1. Step one
2. Step two

## Rules
- Rule one
- Rule two
```

## Rules

1. **Keep it focused.** One skill, one task. If the description covers
 two unrelated tasks, split it into two skills.

2. **Frontmatter is required.** Every skill needs `name`, `description`,
 and `version`. The `engine` field is optional (defaults to `claude`).

3. **Be specific.** Vague instructions like "be helpful" are noise.
 Every line should change the agent's behavior for this task.

4. **Show, do not tell.** Instead of "write clean code", say
 "Prefer `guard` over nested `if let`, match the existing style
 exactly, keep functions under 30 lines."

5. **Do not overwrite existing skills.** Check if a skill with the same
 name already exists before writing. If it does, append a version
 suffix or ask the builder which to keep.

6. **Place the file in the skills folder.** Write to
 `~/.bridgemind/skills/` or the project's `.bridgemind/skills/`
 directory.
