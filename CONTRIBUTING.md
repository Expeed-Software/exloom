# Contributing to exloom

Thanks for your interest in improving exloom. It's an open, MIT-licensed Claude Code plugin, and contributions — new skills, fixes, sharper wording, better templates — are welcome.

## What exloom is made of

exloom is all Markdown plus a little Bash. There's no build step.

- `plugins/exloom/skills/<name>/SKILL.md` — a skill: YAML frontmatter (`name`, `description`) plus the playbook body.
- `plugins/exloom/agents/<name>.md` — a reviewer subagent.
- `plugins/exloom/commands/<name>.md` — a slash command.
- `plugins/exloom/hooks/*.sh` — the opt-in enforcement gate.
- `plugins/exloom/assets/claude-md-templates/` — starting-point CLAUDE.md templates.
- `plugins/exloom/.claude-plugin/plugin.json` — the manifest.

## Ground rules for content

- **Brownfield-first.** Skills defer to the adopter's own conventions (their repo's `CLAUDE.md`). Don't hardcode one org's standards, tools, ports, or tool versions.
- **Keep examples generic.** Don't reference specific companies, internal tickets, products, or other tools by name.
- **Honest, not hype.** Describe what a skill *does*, not what it aspirationally guarantees. exloom's skills are discipline; only the review-gate hooks enforce.
- **Match the voice.** Read a couple of existing skills first and keep the same density and concreteness.

## Adding or changing a skill

1. The folder name must equal the frontmatter `name`.
2. `description` is a *trigger* description — when to use the skill, not what it is.
3. Reference sibling skills as `exloom:<skill-name>`.
4. Reference files by relative path from the skill's own directory.

## Before you open a PR

Run the structural validator:

```bash
bash scripts/validate-plugin.sh
```

It must print `PASSED`. Then:

- Bump the `version` in `plugins/exloom/.claude-plugin/plugin.json` (any plugin change bumps the version).
- Keep the PR focused on one logical change.
- Describe what changed and why.

## Reporting issues

Open a GitHub issue with: what you expected, what actually happened, and a minimal way to reproduce it (the skill or command involved, and the situation that triggered it).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
