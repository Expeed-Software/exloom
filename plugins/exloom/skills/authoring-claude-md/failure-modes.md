# Failure Modes — authoring-claude-md

The failure modes this skill exists to prevent: thought pattern, why it feels right, what actually happens, and the correction.

**1. "I know what conventions this project should use."**

Thought pattern: you have opinions about best practices — modern frameworks, clean architecture, certain naming styles — and you write the CLAUDE.md based on those opinions rather than what the code shows.

Why it feels right: best practices are best practices. The project would benefit from following them.

What happens: the CLAUDE.md documents a codebase that does not exist. Claude follows the CLAUDE.md, produces code that clashes with the actual codebase style, and every developer has to manually fix the mismatch on every task.

Correction: the codebase tells you what conventions it uses. Read the code. Document what is there, not what you wish were there.

**2. "The existing CLAUDE.md is wrong, let me fix it."**

Thought pattern: you see something in the existing CLAUDE.md that contradicts your understanding of the project or what you consider technically correct.

Why it feels right: accuracy matters. Wrong documentation is arguably worse than no documentation.

What happens: you overwrite decisions the team made deliberately. The "wrong" entry might be an intentional workaround, a team preference, or context you lack entirely.

Correction: propose changes with explanations. Let the user decide. The existing file represents team decisions you were not part of making.

**3. "Baselines should always apply."**

Thought pattern: baselines exist for a reason. Consistency across your org's projects reduces cognitive load when switching between them.

Why it feels right: standardization is valuable, and exceptions dilute the standard.

What happens: you override a working convention with a baseline that does not fit the project's reality. A repo with 60% coverage and no test infrastructure for legacy modules gets "80% required" — creating a mandate nobody can meet without a multi-sprint investment.

Correction: baselines are defaults for new code in the absence of existing conventions. Existing code that works differently is not wrong — it is context that the baseline did not anticipate.

**4. "I'll just use the Spring template — it's close enough."**

Thought pattern: the project is Java, and Spring is the most common Java framework in your org. The template covers most of what is needed.

Why it feels right: the templates are similar enough that it will work. Java is Java.

What happens: a Micronaut project gets Spring conventions — wrong annotation style (`@Inject` vs `@Autowired`), wrong testing approach (Micronaut Test vs Spring Test), wrong build plugin configuration. Developers follow the CLAUDE.md and produce code that fails to compile.

Correction: confirm the exact framework before choosing a template. Read the build file dependencies. A `pom.xml` with `spring-boot-starter-web` and a `build.gradle` with `io.micronaut:micronaut-http-server-netty` are fundamentally different projects that need different templates.

**5. "The CLAUDE.md is done, I'll move on."**

Thought pattern: you have written a thorough document and are confident it accurately reflects the codebase based on your analysis.

Why it feels right: the document matches what you observed across multiple files.

What happens: you commit without user review. The user discovers it contains a subtle error — the wrong test command, a misidentified framework version, or a convention from one module presented as a project-wide standard. The CLAUDE.md now actively misleads Claude on every task.

Correction: always present the draft for review before writing it to disk. The user knows their project better than a scan of 5 files can reveal. A two-minute review catches errors that would cost hours across the team.
