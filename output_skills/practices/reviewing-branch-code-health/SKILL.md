---
name: reviewing-branch-code-health
description: Ranks the Code Health of every code file a branch changed, worst score first, with each file's code smells and whether the change improved or degraded it. Use before a PR to triage which changed files need refactoring, or when asked to score a branch's code health with CodeScene.
---

STARTER_CHARACTER = 🩺

Score every code file a branch changed, rank the unhealthiest first, and show each file's current smells plus whether the branch pushed it up or down. Backed by the CodeScene MCP server.

## Prerequisites

The CodeScene MCP server must be installed and configured, and the working directory must be inside a git repository. Every CodeScene tool needs an **absolute** file path. If a tool call errors unexpectedly, call the CodeScene MCP `verify_installation` tool with the repository path and report the failing checks — do not continue with partial data.

## The score scale — internalize this before ranking

Code Health runs from **10.0 (optimal) down to 1.0 (worst)** — a *lower* number is *worse*. Bands:

- 🔴 **1.0–3.9** — severe technical debt
- 🟡 **4.0–8.9** — problematic technical debt
- 🟢 **9.0–9.9** — healthy
- 🟢 **10.0** — optimal

"Lowest on top" therefore means **unhealthiest first**. Do not invert this.

## What the tools actually return

- `code_health_review(file_path)` → `{"score": <10.0..1.0>, "review": [...]}`. Each `review` entry is one smell: `category` (its name, e.g. "Bumpy Road Ahead"), `functions[]` (each with `title`, `details`, `start-line`, `end-line`), and `indication` (severity — higher is worse). An empty `review` means a clean file. This one call yields both the score and the findings.
- `analyze_change_set(base_ref, git_repository_path)` → `{"results": [...], "quality_gates": "passed"|"failed"}`, where each result has `name` and `verdict` (`improved`/`degraded`/`stable`). It reports **only files whose code smells changed** (introduced or fixed) — a file with no smell delta is absent whether it was added or modified, so a new *messy* file appears but a new *clean* one does not. Treat it as a trend and gate overlay, never as the list of changed files.

## Workflow

**1. Resolve the comparison base (three-dot / merge-base).**

```bash
DEFAULT=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
DEFAULT=${DEFAULT:-$(git rev-parse --verify --quiet main >/dev/null && echo main || echo master)}
BASE=$(git merge-base "$DEFAULT" HEAD)
```

`BASE` (the SHA) scopes the review to what *this branch* introduced and excludes changes the default branch gained after the fork. If the user names an explicit base, take its `merge-base` with HEAD unless they ask to compare against the raw tip. If `BASE` equals HEAD (no divergence — e.g. sitting on the default branch), there are no branch changes; say so and stop, offering to compare against a base ref they name.

**2. List the changed code files — from git, the source of truth.**

```bash
git diff --name-status --diff-filter=d "$BASE" HEAD
```

Each line is `<status>\t<path>` (`A` added, `M` modified, `R` renamed) — keep the status; step 4 needs it. Keep only CodeScene-supported source extensions (everything else has no Code Health):

```
.c .cc .cpp .cxx .h .hh .hpp .hxx .ipp .cs .java .groovy .js .mjs .cjs .sj .ts .mts .cts
.jsx .tsx .vue .m .mm .scala .py .pyi .swift .go .dart .vb .php .rs .rb .kt .kts .pl .pm
.erl .hrl .ex .exs .clj .cljc .cljs .ps1 .psm1 .psd1 .tcl .cls .trigger .tgr .brs .bs .efx .emx
```

Empty list → report that no code files changed and stop.

**3. Score and diagnose each file.** Call the CodeScene MCP `code_health_review` tool with each file's **absolute path**. Take `score` and the `review[]` smells; order a file's smells by `indication` descending so the worst shows first. If a file's review errors, keep the row with `score` shown as `—` and a short note — never fabricate a score or smells.

**4. Overlay branch impact.** Call the CodeScene MCP `analyze_change_set` tool once with `base_ref=$BASE`. Build a map from `results[].name` to `verdict`. A file present in the map takes its verdict (`improved`/`degraded`/`stable`). A file absent from the map had no smell change: mark it `new` if git listed it as added (status `A`), otherwise `stable`. Surface the top-level `quality_gates` as the headline.

**5. Sort ascending by `score`** — unhealthiest on top. Ties: `degraded` above `stable` above `improved` above `new`.

**6. Render the table.** Lead with branch, base, file count, and the quality gate, then the ranked rows.

## Output format

A sensible default — adapt to context (drop Trend if no base resolved; widen Findings when one file dominates):

```
## Branch Code Health — feature/checkout vs main (3 files) · Quality gate: FAILED ❌

| File | Health | Trend | Findings |
|------|--------|-------|----------|
| src/payments/charge.py | 3.2 🔴 | degraded ⬇️ | Bumpy Road Ahead (load_run_results L67–173), Deep Nested Complexity, Large Method |
| src/auth/session.py | 6.8 🟡 | stable ➡️ | Complex Method (authenticate L40–92) |
| src/ui/Button.tsx | 9.4 🟢 | new 🆕 | — |

Rows sorted by Health, worst first. Ask to expand any file for its full CodeScene review.
```

Map the score to its band emoji from the scale above. Map `verdict` to Trend: `degraded` ⬇️, `stable` ➡️, `improved` ⬆️. For a file absent from the change set, use `new` 🆕 if git marked it added, else `stable` ➡️.

## Anti-examples

- Using `analyze_change_set.results[]` as the changed-file list — it omits every file whose code smells did not change (clean or health-unchanged, added or modified); `git diff` is the source of truth for what changed.
- Passing `base_ref="main"` (a name) instead of the `merge-base` SHA — that is a two-dot diff and pulls in files teammates changed after you branched.
- Passing unsupported files (`.md`, `.json`, lockfiles) to `code_health_review` — filter by the supported-extension list first; it hard-errors otherwise.
- Sorting by filename, trend, or discovery order — the ranking axis is `score`, ascending.
- Treating a high score as the problem — 1.0 is the worst, 10.0 the best.
- Fabricating a score for a file whose review errored — leave it `—` with a note.
- Reporting only the trend or only the score — the skill promises both: the score is the *state*, the trend is the *direction*.
