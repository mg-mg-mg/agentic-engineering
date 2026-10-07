# One Engineer, an Agent Team: How I Ship a Production Product with AI Agents

![Replay: Issue #499 to production in about two hours, every step by agents except two owner approvals](./agentic-replay.gif)

*Replay from real repository timestamps (KST, 2026-10-07): a browser agent finds a bug, a lead session opens the fix, a separate reviewer approves at fixed SHAs, the owner authorizes merge and deploy. Issue to production deploy: 2 h 01 m.*

**Visual version:** [index.html](./index.html) (rendered page link will be added when published)

*Mingyun Chae, October 2026. Case study of the delivery system behind [TriAstra](https://triastra.ai) and a client engagement in Singapore. Product source code is private; this document describes the process, not the product code.*

## TL;DR

I run software delivery as a small organization in which AI agents do almost all of the implementation, review, verification, and bookkeeping, and I act as owner, architect, and final authority on irreversible decisions.

| Metric | Value |
| --- | --- |
| TriAstra commits since first commit (2026-01-05) | 10,143 |
| PRs merged since moving to a PR-gated, review-required flow (Sep 2026) | 225 |
| PRs merged per day, Oct 3-6 2026 | 34 / 44 / 44 / 45 |
| Issues tracked in the delivery queue | 310 |
| Product surfaces | Web app (live), iOS and Android apps, admin/ops console, ChatGPT app integration (MCP), background workers |
| Languages shipped | 7 locales; 6 managed through AI review gates |
| Client engagement (Singapore B2B platform, 1 month) | 715 PRs authored, 702 merged, median time-to-merge 1.3 h, 98.7% of repo commits |
| Pre-merge E2E gate on that engagement | 33 min down to 2-4 min |

Every merged PR in the gated flow requires review by a *different* agent than the author, against fixed head/base SHAs, plus checks reproduced by a separate verifier. Volume is the output; the gates are the product.

## 1. The operating principle: owner attention is the scarcest resource

The repository's root contract (`AGENTS.md`, about 63 KB plus nested files and task skills) starts from one rule: an agent that stops to ask for a decision it could make itself costs more than a reversible mistake that it catches and fixes.

Decision rights are explicit:

| Decision | Who decides |
| --- | --- |
| Technical design, root-cause scope, refactoring, slicing, test strategy, task order | Agent decides, acts, reports the reason |
| Defects found while working, tooling recovery, Issues, labels, branches, worktrees, PRs, docs and rule updates | Agent acts, then records |
| Deployment, store submission, payments, production data writes, external messages, spending, credentials | Owner, asked once with a recommendation |
| Product direction, pricing, user-facing policy, final Korean copy | Owner, asked once; agent keeps working on everything else |

Agents "work the queue": when a task ends they start the next authorized one instead of asking "what next?". Reports have three parts: done (with evidence), started next, needs an owner decision.

## 2. The system

```mermaid
flowchart TB
  O["Owner<br/>product, priorities, irreversible approvals"]
  subgraph L["Agent lanes"]
    A["Interactive lead sessions<br/>one per workstream<br/>workers in isolated worktrees"]
    B["Unattended Issue pool<br/>4 LaunchAgent workers, 180 s tick<br/>author → reviewer → verifier → guarded merge"]
    C["Browser agent<br/>live E2E, payments test mode,<br/>i18n/UX + dashboard audits"]
  end
  G[("GitHub Issues / PRs / Project")]
  Q{{"Gates: compile/generate-time static gate · tests · visual regression · exact-hash locale review · release evidence"}}
  O --> A & B & C
  A --> G
  B --> G
  C -- files Issues --> G
  G --> Q
```

### 2.1 Interactive lead sessions

Each workstream has a long-lived lead session in a terminal agent harness. Tooling evolved with the work: TriAstra started on Codex and Claude Code, moved through oh-my-pi (omp), and now runs entirely on jcode; the client engagement used Codex and omp, then consolidated on omp. The rules live in the repository, not in a tool, so switching harnesses did not reset the process. A lead owns design, integration, and final verification, and delegates bounded slices to at most two workers, each in its own git worktree with explicit file ownership, acceptance criteria, and a stop condition. Generated surfaces (OpenAPI clients, SQLx metadata, l10n files, fixtures) get exactly one owner lane per task so agents never fight over the same files.

### 2.2 The unattended Issue pool

Four macOS LaunchAgent workers wake every 180 seconds and each claims at most one unowned P1/P2 bug or maintenance Issue from a complete Project/PR/dependency snapshot. Payment work, Owner holds, unresolved dependencies, and anything already owned by a branch or PR are excluded. For each claim:

1. **Author**: a coding model runs in an offline, minimal-read worktree sandbox with no GitHub or provider credentials and no access to secrets. It can implement and run local checks, but cannot commit, push, or reach the network.
2. **Trusted dispatcher**: validates Issue and Project state, stages and reviews the diff with the trusted review script, disables candidate git hooks, publishes the PR, and verifies the exact remote head.
3. **Independent reviewer**: a separate read-only model process reviews the fixed head/base SHAs against the current Issue acceptance criteria and chooses which checks are needed.
4. **Verifier**: a separate credentialless process runs those checks and must leave the reviewed head and worktree unchanged.
5. Findings or failures go back to the same author lane. Every revision needs a new head, a fresh review, and passing verification. The loop runs until mergeable or a five-hour budget expires.
6. **Guarded merge**: the dispatcher saves a merge intent, squash-merges pinned to the reviewed head, then verifies parent, tree, and Issue state, and posts the risk verdict, exact commands, exit codes, and remaining criteria to the PR.

Nothing unattended can deploy, submit to app stores, touch production data, move money, change credentials, or send external messages.

### 2.3 A browser agent as a teammate

A browser agent (Aside) handles everything that needs a real logged-in browser: end-to-end payment flows in test mode (checkout, refund, period-end cancel, revoke), live i18n and UX audits across all locales, and read-only audits of ops, analytics, and observability dashboards. It talks to the coding sessions through a file mailbox inside the repository and the harness debug socket, and turns findings into GitHub Issues that the coding lanes pick up. One example: during a payments migration it found that refunded reports kept generating (about 260k LLM input tokens per report). That became an Issue, was fixed by a coding lane, and was deployed the same day.

## 3. The gates that make speed safe

- **Find errors at compile, analyze, or generation time, not at runtime.** A single cross-language static gate covers Rust, generated API clients, Flutter, TypeScript, Python, Shell, and Terraform. Contract-first REST APIs generate typed clients so API drift fails the build.
- **Author-reported green checks never count.** Review and verification must be reproduced by a different process at fixed SHAs, even for a docs-only PR.
- **Root cause plus a ratchet.** A fix is done only when the root cause is named and a regression test, ratchet, or gate stops it from returning.
- **Visual regression** with deterministic Flutter goldens and Chromium screenshots of app, widget, and public pages.
- **Locale quality gate:** for AI-managed locales, a string ships only after seven independent locale passes over the exact text hash; the owner natively reviews Korean.
- **Concurrency guards:** Cargo build slots shared across worktrees, a fail-closed lease on `main` for release and integration, `--force-with-lease` with an observed SHA for any history rewrite, serialized merges.
- **Evidence over claims:** every report states the commands run, observed results, and checks that could not run. Unverified claims are labeled as such.

## 4. What I learned

1. **Throughput is cheap; trust is expensive.** The bottleneck moved from writing code to defining acceptance criteria and building gates that make agent output trustworthy without me reading every line.
2. **Separate the roles.** The same model reviewing its own work misses the same things. Separate author, reviewer, and verifier processes with different permissions catch far more.
3. **Least privilege for agents.** The author needs no network and no secrets. Credentials live only in the trusted dispatcher, and only for the specific write it is about to make.
4. **Write the rules where agents read them.** Decision rights, workflows, and domain facts live in versioned repo docs, so every new session starts with the same contract and rules improve through PRs.
5. **Spend human attention on the irreversible.** I approve deployments, payments, pricing, and user-facing policy. Almost everything else is delegated and audited.

## 5. Same system, client context

On a one-month on-site contract for a Singapore startup-accelerator B2B platform (existing Django + React codebase), the same approach (run on oh-my-pi after starting on Codex) let me act as the sole full-stack engineer: a spreadsheet-only process became a 15-screen prototype, then a real server and three role-based portals in six days; I built a meeting engine (availability, booking locks, reschedule state machine, time zones and DST, .ics), locked down 15 unauthenticated APIs and tiered 30 write APIs, removed 87+ legacy templates, and cut the pre-merge E2E gate from 33 minutes to 2-4 minutes. 715 PRs authored, 702 merged, client rating 5.0/5.

---

Contact: coalsrbs7@gmail.com · GitHub [mg-mg-mg](https://github.com/mg-mg-mg)
