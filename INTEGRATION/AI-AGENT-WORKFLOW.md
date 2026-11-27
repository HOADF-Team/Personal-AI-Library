# AI agent workflow: Skills + AI-Toolbox

**Purpose:** one repeatable procedure for using the organization's Skills and tool records together.  
**Repositories:** [Personal-AI-Library](https://github.com/HOADF-Team/Personal-AI-Library) and [AI-Toolbox](https://github.com/HOADF-Team/AI-Toolbox).  
**Status:** operational guidance; it does not itself install software or make GitHub Skills load automatically in every AI product.

## 1. Responsibilities

- **Personal-AI-Library** defines *how to do the work*: task workflow, checks, decision points, safety rules and reusable references.
- **AI-Toolbox** describes *which concrete tools may help*: upstream source, license, platforms, dependencies, installation/use instructions, verification evidence and limitations.
- **The active runtime** is where the task is actually executed. A catalog entry is not proof that software is installed or accessible there.

Keep these responsibilities separate. Do not copy full tool records into Skills or duplicate Skill procedures in the Toolbox.

## 2. Standard procedure for every task

### Step A — identify the task and execution target

1. Read the repository's own `AGENTS.md`, project instructions and relevant user requirements first.
2. Identify the actual target: current ChatGPT session, Codex environment, local workstation, VPS, container, CI runner, connected service, or a combination.
3. Identify constraints: operating system, language/runtime version, network access, permissions, data sensitivity, budget, deadlines and whether the work touches production.
4. Do not assume that a tool available to the assistant is installed on the user's computer, or that a GitHub Actions runner has the same network access as the user's environment.

### Step B — select only relevant Skills

1. Consult the [Skills catalog](../CATALOG.md) and the relevant `skills/<skill-name>/SKILL.md`.
2. Use the Toolbox [Skill → Tool map](https://github.com/HOADF-Team/AI-Toolbox/blob/main/CATALOG/SKILL-MAP.md) to discover likely supporting tools.
3. Load only the selected Skill's `SKILL.md` and the references/scripts needed for the current task. Do not load all Skills by default.
4. For cryptocurrency systems, consider `crypto-security` together with `devops-vps`, `code-audit` and `trading-bot-audit` as needed; keep security review separate from authorization to change production.
5. If multiple Skills apply, use the smallest useful combination. Resolve conflicting instructions in favor of the current project requirements, repository-specific instructions and safety constraints; report material conflicts.
6. A Skill is guidance, not authorization. It cannot grant permission to spend money, access accounts, publish content, alter production systems or perform financial transactions.

### Step C — discover and assess tools

1. Search `AI-Toolbox/CATALOG/tools.json` and existing `TOOLS/**/TOOL.md` records before searching the web or proposing a new dependency.
2. Read the full record for each plausible tool. Check its current status, version/pinning guidance, operating-system support, license, dependencies, permissions, network requirements, cost, installation effects and limitations.
3. Follow [AI-Toolbox environment discovery](https://github.com/HOADF-Team/AI-Toolbox/blob/main/TESTS/ENVIRONMENT-DISCOVERY.md) in the target environment when available. Prefer read-only discovery first.
4. When inventory is available, run the Toolbox preflight: generate `inventory.json` with `scripts/inventory.py`, match it using `scripts/match_inventory.py`, then check only the selected Skill IDs with `scripts/check_skill_tools.py --skill <skill-id> --matches matches.json`. Interpret `ready` as declared prerequisites detected, `blocked` as all alternatives explicitly missing, and `unknown` as insufficient probe evidence. This is not a functional test; review the Skill and TOOL.md records and perform task-specific checks.
5. Verify actual availability in the target environment using the documented version or health check. Distinguish:
   - catalog record exists;
   - executable/package is installed in this runtime;
   - tool is available through a connector or hosted service;
   - software is installed on the user's separate device.
6. Reuse a compatible existing installation. Do not reinstall just because the catalog says `tested`.

### Step D — decide whether installation is justified

Install only when the task needs the capability and no suitable available alternative exists.

Before installation:
- verify the official source, maintainer, license and redistribution conditions;
- inspect installer scripts, package metadata and expected side effects;
- check version constraints, transitive dependencies, permissions, telemetry, network access, account/API-key requirements and costs;
- prefer pinned versions, official package managers, checksums/signatures and isolated environments;
- choose the least-privileged installation scope and a reversible method.

Do not install software on the user's device unless the user has requested it and the target device/environment is clear. Do not make purchases, start paid subscriptions, create credentials, change account settings, or modify production systems without explicit approval. Never put secrets in either repository.

If installation is blocked or unsafe, stop and report the exact blocker. Do not silently substitute an unreviewed package.

### Step E — use and verify

1. Follow the Skill workflow and the tool record's documented usage.
2. Use the narrowest permissions and minimum data required.
3. Prefer read-only or dry-run modes before write operations.
4. Run the documented smoke test or task-specific validation after setup and after meaningful changes.
5. Record the exact environment, tool version, command/check, result and limitations.
6. Separate verified observations from assumptions. A successful smoke test proves only the tested scope; it does not establish universal compatibility.

### Step F — maintain the libraries

When a tool is newly discovered or its status changes:

1. Update or create `TOOLS/<category>/<tool-id>/TOOL.md` with source, license, version, platforms, dependencies, security notes, install/use/removal instructions, test evidence and limitations.
2. Update `CATALOG/tools.json` consistently. Keep IDs and record paths stable.
3. Use the status definitions in the Toolbox `AGENTS.md`: `discovered`, `reviewed`, `tested`, `ready`, `blocked` or `deprecated`. Never promote a status without evidence.
4. Update `CATALOG/SKILL-MAP.md` only when the tool meaningfully supports one or more real Skills, or when a mapping/limitation changes.
5. Run the Toolbox catalog and relevant tests. Submit changes through a pull request; do not silently claim that the public catalog has changed until the PR is merged.
6. If a Skill's workflow itself changes, update its source in Personal-AI-Library, run `python validate_skills.py` and the relevant tests, then submit a separate PR there.

Do not add every candidate. Add only tools that solve a concrete gap and pass source/license/security review.

## 3. Safety and approval gates

Explicit user approval is required before:
- installing on a user's personal device or changing a production environment;
- using paid APIs, paid services, subscriptions or resources that incur charges;
- accessing private accounts or using credentials beyond an already authorized scope;
- sending messages, publishing, uploading customer data or making externally visible changes;
- destructive operations, migrations, permission changes or irreversible actions;
- placing live financial orders, transferring funds, changing leverage/margin settings or enabling live trading.

For financial/crypto tasks, default to public market data, offline analysis and paper trading. Never request or store exchange secrets in these public repositories. Network restrictions in CI must be reported as environment limitations, not misrepresented as proof that an adapter is broken.

## 4. Reporting format

For substantive work, report:

- **Skill(s) used:** exact Skill IDs and why they apply.
- **Tools used:** exact tool names and versions, or state that no external tool was needed.
- **Target environment:** where checks actually ran.
- **Checks:** commands/tests and pass/fail/blocked results.
- **Changes:** files/repositories/PRs changed.
- **Limitations:** what remains unverified or requires user approval.

Never say “installed”, “tested”, “available” or “deployed” without specifying the environment and evidence.

## 5. Runtime compatibility note

GitHub repositories are source-of-truth storage, not an automatic runtime loader. Codex can use Skills installed in its configured Skills directory; another AI product may require a different import/installation mechanism. If Skills are not loaded by the current product, read the relevant `SKILL.md` directly for this task and state that it was loaded manually. Do not claim that merely publishing a Skill on GitHub makes it active in the current session.

## 6. Source of truth

- Skills and their references: [Personal-AI-Library/skills](https://github.com/HOADF-Team/Personal-AI-Library/tree/main/skills)
- Skills index: [Personal-AI-Library/CATALOG.md](https://github.com/HOADF-Team/Personal-AI-Library/blob/main/CATALOG.md)
- Tool records and catalog: [AI-Toolbox/TOOLS](https://github.com/HOADF-Team/AI-Toolbox/tree/main/TOOLS) and [tools.json](https://github.com/HOADF-Team/AI-Toolbox/blob/main/CATALOG/tools.json)
- Mapping: [AI-Toolbox/SKILL-MAP.md](https://github.com/HOADF-Team/AI-Toolbox/blob/main/CATALOG/SKILL-MAP.md)
- Tool contribution/safety rules: [AI-Toolbox/AGENTS.md](https://github.com/HOADF-Team/AI-Toolbox/blob/main/AGENTS.md)
