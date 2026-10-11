# exloom — Privacy

**Short version: exloom runs entirely on your machine, collects nothing, and sends nothing to Expeed Software or any third party.**

exloom is a Claude Code plugin made of Markdown skills, shell hooks, and small helper scripts. It operates on your own repository and its git history, inside your own Claude Code session.

## What exloom does with data

- **No data collection.** exloom has no telemetry, analytics, tracking, or "phone home" of any kind. It ships no MCP server and no network service of its own.
- **No transmission to Expeed or third parties.** Nothing you do with exloom is sent to Expeed Software.
- **Local storage only.** The evidence exloom produces — review checklists and provenance records — is written to `.claude/reviews/` inside *your own* repository and committed to *your own* git history. It stays with you.
- **Your git identity.** A provenance record includes the author name/email from your local `git config` and the model id reported by your Claude Code session. exloom writes this into your own repo's files; it does not send it anywhere.

## Nuances worth stating plainly

- **exloom runs inside Claude Code.** Claude Code is an Anthropic product with its own data handling and terms; exloom does not change or add to that — it only reads local files and runs local commands.
- **The security review invokes third-party tools.** For a Tier 3 change, or one touching input, auth, secrets, data exposure or dependencies, the review gate dispatches the `exloom:security-auditor` reviewer agent. It runs whatever security scanners you have installed locally (e.g. `gitleaks`, `semgrep`, `npm audit`, `pip-audit`, `osv-scanner`) and checks that each new dependency exists on its public package registry (e.g. npm, PyPI). Those tools and registries have their **own** data behavior — `npm audit`, for one, sends your dependency list to the npm registry. exloom adds no data flow of its own.
- **Pull requests only where you say.** `exloom:capturing-learnings` shows you each proposed CLAUDE.md change before making or committing it, and opens a pull request only on a repository you name, after you agree.

## Contact

Questions: **support@expeed.com**

_This document describes exloom the plugin. It is not legal advice and does not govern Claude Code, your git host, or any third-party tool you choose to run._
