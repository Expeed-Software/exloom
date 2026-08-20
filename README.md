# exloom

**Claude Code plugins from [Expeed Software](https://github.com/Expeed-Software) — disciplined, evidence-based workflows for teams.**

This repository is a Claude Code marketplace. Each plugin is installed and versioned independently; add the marketplace once, then install whichever you need.

MIT-licensed. Works with any Claude Code installation that supports plugins.

## Add the marketplace

```
/plugin marketplace add https://github.com/Expeed-Software/exloom
```

From the terminal: `claude plugin marketplace add https://github.com/Expeed-Software/exloom`

## Plugins

### [exloom](plugins/exloom/) — development workflow

Spec-driven development for teams, with a review gate that's actually enforced. Brainstorm → plan → execute → prove → review, with the plan as an auditable handoff contract between developers, a multi-pass review panel (correctness, cross-layer, adversarial, security), a boot-and-prove smoke test, and an opt-in gate that blocks "done" and `git push` until the review evidence is committed and bound to the reviewed commit.

```
/plugin install exloom@exloom
```

**Requires** Git, Bash, and `jq` or `python3` for the full gate. → [details](plugins/exloom/)

### [exloom-qa](plugins/exloom-qa/) — QA test-case workflow

Turns an Azure DevOps user story into reviewed, traceable, human-executable manual test cases, published to the board and linked to the story only after explicit QA approval. Scales test volume to story complexity, traces coverage against acceptance criteria, learns your application from QA's corrections, and enforces approval with a hook that fails closed.

```
/plugin install exloom-qa@exloom
```

**Requires** the `az` CLI with the `azure-devops` extension. No MCP server, no personal access token. → [details](plugins/exloom-qa/)

## How the plugins relate

exloom is for teams shipping code. exloom-qa is for teams proving it works. They share a mechanic — a human-approved evidence artifact that a hook enforces — applied to code review and to test-case publishing respectively. Neither requires the other; install either alone.

## Versioning and releases

Each plugin carries its own version in its own `plugin.json` and releases on its own schedule. Release tags are prefixed per plugin (`exloom--v1.6.0`, `exloom-qa--v0.2.0`) so the two histories never collide. Installs resolve from the default branch, so merging to `main` is what publishes; tags and GitHub Releases are changelog, not delivery.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Run `bash scripts/validate-plugin.sh` before opening a PR — it validates every plugin in the marketplace.

## License

[MIT](LICENSE). Built by [Expeed Software](https://github.com/Expeed-Software).
