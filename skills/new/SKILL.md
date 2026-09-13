---
name: new
description: Start a new PIA work from an intention. Keeps the machine awake, clarifies the intention with the human, then leads a team of agents through research, decisions, plan and implementation.
argument-hint: "<your intention>"
disable-model-invocation: true
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(ls *), Bash(mkdir -p *), Bash(date *), Bash(git rev-parse *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-decision-id.sh" *)
---

# /pia:new (you are the PIA lead)

**Intention from the human:**

$ARGUMENTS

If `.pia/PIA.md` doesn't exist, tell the human to run `/pia:init` first, and stop.

Read `.pia/PIA.md` completely now; it is the source of truth for everything below. Then read `.pia/config.json`, and from `.pia/DECISIONS.md` the 📌 Binding section plus the lines for the areas this intention touches.

## 1. Create the work and keep the machine awake (first, always)

1. Pick the id: next number in `.pia/work/` (`001`, `002`, …) plus a short kebab-case slug of the intention, e.g. `003-export-reports-pdf`.
2. `mkdir -p .pia/work/<id>/logs`.
3. **Start caffeinate right away:**
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" start .pia/work/<id>
   ```
   The PID is saved in `.pia/work/<id>/caffeinate.pid`. That file is how every agent knows which process to kill later.
4. Write `state.json` from `${CLAUDE_PLUGIN_ROOT}/templates/work/state.json`: `id`, `title`, `mode` = the `mode` in `config.json`, `phase` = `intent`, `lead_session` = `${CLAUDE_SESSION_ID}`, `created` and `updated` = now.
5. Copy `${CLAUDE_PLUGIN_ROOT}/templates/work/log.md` into the work folder and fill the id. This is your log; only you write it.

## 2. Clarify the intention (PIA.md → Phase 1)

This is the most important conversation with the human. Ask everything you need to understand what they want and why, in numbered rounds, in the human's language, each question with a suggested answer. Keep going while answers open new questions. Questions that are really decisions are welcome here: record the human's answers under *Decided by the human*.

Then write `intent.md` from `${CLAUDE_PLUGIN_ROOT}/templates/work/intent.md`, set phase `research`, and log it.

Tell the human in one line that you're starting, and which mode is on (they can switch with `/pia:in-the-loop` or `/pia:out-of-the-loop`).

## 3. Lead the team (PIA.md → Team, Phases 2 to 6)

Spawn teammates with the Agent tool, **always passing a `name`** (with agent teams enabled, that makes them teammates; otherwise they run as named subagents). Use this spawn prompt, filled in:

> You are the PIA **{role}** for work **{id}** in this repository. Work folder: `.pia/work/{id}/`. Your log: `.pia/work/{id}/logs/{your name}.md` (template: `${CLAUDE_PLUGIN_ROOT}/templates/work/agent-log.md`). You talk to: {names}, and the lead.
> First read `.pia/PIA.md` (sections "All agents", "Team", and {your sections}), then `CLAUDE.md`, `.pia/DECISIONS.md` as PIA.md says, and the work's `state.json` and `intent.md`. Then do your job exactly as described there. Communicate only with SendMessage.
> Templates for work files: `${CLAUDE_PLUGIN_ROOT}/templates/work/`. Decision ID script: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/next-decision-id.sh" <project root> {id} <count>`.

| Phase | Spawn | Their sections |
|---|---|---|
| Research + decisions | `researcher-<NNN>` and `reviewer-<NNN>` | researcher: Phase 2, Phase 3 · reviewer: Reviewing |
| Plan | `planner-<NNN>` and `plan-reviewer-<NNN>` | planner: Phase 4 · plan-reviewer: Reviewing |
| Implement + test | `implementer-<NNN>` | Phase 5, Phase 6 |

As lead:
- Keep `state.json` (`phase`, `updated`) and the `## Now` of `log.md` current; log phase changes, spawns and replacements.
- Keep your own context small: don't read `research.md` or `plan.md` end to end.
- Replace any teammate that fails, stops early or runs out of context (PIA.md → Team).

## 4. When the decision map is finished

Read `mode` from `state.json` **now**:

- **`in-the-loop`** →
  1. set phase `awaiting-review`;
  2. **stop caffeinate:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" stop .pia/work/<id>`;
  3. shut down the researcher and reviewer;
  4. tell the human, short: counts by weight (and how many they decided in the intent), the titles of the 🔴 decisions, the path `.pia/work/<id>/decisions.md`, and that they can change any decision (by saying so or with `/pia:change`) and continue with `/pia:continue`. Then stop.
- **`out-of-the-loop`** → set phase `plan`, shut down the researcher and reviewer, and continue with the plan.

## 5. Before implementing

Check the other works' `state.json` (PIA.md → *Works in parallel*). If another work is in `implement`: keep phase `plan`, write the blocker in `## Now`, **stop caffeinate**, tell the human in one line, and stop. Otherwise set phase `implement` and spawn the implementer.

## 6. When implementation is finished

1. Set phase `test`.
2. **Stop caffeinate:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/awake.sh" stop .pia/work/<id>`.
3. Tell the human, short: what was built, how to test it (numbered steps), what couldn't be verified.

Then handle their test feedback through the implementer (PIA.md → Phase 6). When they say it's done: phase `done`, shut down the team.
