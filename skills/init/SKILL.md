---
name: init
description: Set up PIA (Decision Driven Development) in this repository. Creates .pia/, imports docs/RULES.md into DECISIONS.md, moves CLAUDE.md to AGENTS.md and points it at PIA, and configures auto-compaction and agent teams.
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(git rev-parse *), Bash(git mv *), Bash(git ls-files *), Bash(ls *), Bash(mkdir -p *), Bash(touch *), Bash(mv *), Bash(rm *), Bash(cp *), Bash(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/pia-settings.py" *)
---

# /pia:init

Set up PIA in the current repository. **Safe to run again:** it refreshes `.pia/PIA.md`, `.pia/.gitignore` and the settings, and never overwrites decisions, config or works.

Plugin templates are in `${CLAUDE_PLUGIN_ROOT}/templates/project/`.

## 1. Understand the repo

Find the root (`git rev-parse --show-toplevel`, else the current directory). Read `CLAUDE.md`, `AGENTS.md`, `docs/RULES.md`, the README and the main manifests, only enough to write a correct `AGENTS.md` if one is missing. Don't crawl the codebase.

## 2. Create `.pia/`

| File | From | When |
|---|---|---|
| `.pia/PIA.md` | `templates/project/PIA.md` | always (the plugin owns it) |
| `.pia/.gitignore` | `templates/project/gitignore` | always |
| `.pia/DECISIONS.md` | `templates/project/DECISIONS.md` | only if missing |
| `.pia/config.json` | `templates/project/config.json` | only if missing |
| `.pia/work/.gitkeep` | empty | only if missing |

If an existing `config.json` still says `"mode": "review"` or `"mode": "auto"` (older PIA), rename it to `in-the-loop` or `out-of-the-loop`, and do the same in any `state.json` under `.pia/work/`.

## 3. Import `docs/RULES.md` into 📌 Binding

Skip this step if `docs/RULES.md` doesn't exist, or is already the PIA pointer.

1. For each rule, in order, add an entry under `## 📌 Binding` in `.pia/DECISIONS.md`:
   ```
   ### D-NNN · {rule title}  [{area}]  (was Rule N)
   {the rule's full text, verbatim, including "Where it's enforced"}
   ```
   Use the next free `D-NNN` (start at `D-001` in a fresh file). Pick a short lowercase area for each rule (`i18n`, `design`, `testing`…). Keep the text exactly; don't summarize. Leave out the file's generic scaffolding (the intro and "The one rule about rules"); `PIA.md` covers that.
2. For each imported rule, add its line under `## All decisions`:
   `D-NNN  📌  [{area}] {title} · imported from docs/RULES.md · approved`
3. Replace `docs/RULES.md` with this pointer:
   ```markdown
   # Rules moved

   Binding rules now live in [`.pia/DECISIONS.md`](../.pia/DECISIONS.md), section **📌 Binding**.
   Old rule numbers are kept there as "(was Rule N)".
   ```

If `docs/RULES.md` has no rules (only the empty scaffold), just replace it with the pointer.

Import every rule verbatim, but **flag in the report** any rule that refers to the old workflow (manual test gates, `.claude/plans/`, `.claude/WORKFLOW.md`, `/research` · `/plan` · `/implement`) or to paths that don't exist in this repo; the human may want to change it with `/pia:change`.

## 4. Move `CLAUDE.md` to `AGENTS.md` and point it at PIA

Project instructions live in **`AGENTS.md`**, so any agent — not just Claude Code — reads the same file. Claude Code 2.1.278+ loads `AGENTS.md` exactly where it would load `CLAUDE.md`, **but only when the project has no `CLAUDE.md` of its own.** So this is a move, not a copy: leaving both behind means the `AGENTS.md` is silently ignored.

**If `CLAUDE.md` exists and `AGENTS.md` doesn't:** move it (`git mv CLAUDE.md AGENTS.md` when it is tracked, else `mv`). Keep the content; the next steps edit it in place.

**If both exist:** if `AGENTS.md` is a symlink to `CLAUDE.md` (the old PIA setup), delete the symlink and then move `CLAUDE.md` onto it. If both are real files, merge `CLAUDE.md` into `AGENTS.md`, keeping everything from both and dropping exact duplicates, then delete `CLAUDE.md`. Say in the report that you merged them.

**If neither exists:** create a short `AGENTS.md` (under 50 lines): project name and one sentence, Stack, Commands, non-obvious Architecture and Conventions. Only what an agent can't infer from the code. Never invent commands.

Then, in `AGENTS.md`: remove only the lines or sections that point agents at the old workflow (the `docs/RULES.md` pointer and any `.claude/WORKFLOW.md`, `/research`, `/plan`, `/implement` pointers), keep everything else exactly as it is, and add (or refresh) this section at the end:

```markdown
## PIA
This project uses PIA (Decision Driven Development).
- **`.pia/PIA.md`**: how agents work here: a talk that is also the research → decisions → implement → test. Read it before any PIA work.
- **`.pia/DECISIONS.md`**: every decision made in this project. 📌 Binding decisions are never re-decided; the rest are the default unless there is a stated reason to deviate, which is itself a new decision.
```

Don't touch `.claude/research/`, `.claude/plans/`, `.claude/WORKFLOW.md` or old commands.

## 5. Settings

Run:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/pia-settings.py" "<repo root>"
```

It merges into `.claude/settings.json`: `autoCompactWindow` (from `.pia/config.json`, default 600000 tokens) and `env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"`.

## 6. Report

Short, in the human's language:
- what was created or changed (bullets), including the move from `CLAUDE.md` to `AGENTS.md`;
- how many rules were imported, if any, and which ones were flagged;
- **restart Claude Code in this project** so auto-compaction and agent teams take effect;
- if `claude --version` is below 2.1.278, say that `AGENTS.md` may not be read by Claude Code yet and they should update;
- next: `/pia:new <your intention>`.
