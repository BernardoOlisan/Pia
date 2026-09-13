# PIA: Decision Driven Development

This file is the **source of truth** for how agents work in this repository. Any coding agent can read it and follow it. In Claude Code, the `pia` plugin exposes it as `/pia:*` commands.

It is owned by the plugin and refreshed by `/pia:init`. Don't edit it by hand. Anything specific to this project belongs in `.pia/DECISIONS.md`.

## The idea in one minute

- Long, exhaustive documents are for agents. The human reads a **decision map**.
- **Everything written is a decision.** The human reviews the decisions that govern the work, not the work itself.
- **Agents always decide.** The recommended answer *is* the decision, with its reason. The human can change any decision at any time, and the system works out what depends on it.
- **The work never stops** because the human is away or an agent ran out of context: logs, reviewers, replacements and automatic compaction keep it going.
- **Decisions become memory.** Past decisions shape future recommendations.

## Layout

```
.pia/
├── PIA.md                 this file
├── DECISIONS.md           project memory: 📌 Binding decisions (full text) + one line per decision
├── config.json            project defaults: mode, auto-compact window (tokens)
├── .gitignore             ignores *.pid
└── work/<NNN-slug>/       one folder per intention (feature, fix, anything)
    ├── state.json         id, title, mode, phase, lead session
    ├── intent.md          👤 the clarified intention (short)
    ├── research.md        🤖 exhaustive research
    ├── decisions.md       👤 the decision map
    ├── plan.md            🤖 exhaustive plan
    ├── log.md             🤖 running log, used to resume after compaction or a restart
    └── caffeinate.pid     temporary, never committed
```

👤 written for the human. 🤖 written for agents only; the human never has to read it.

## Phases

```
intent → research → decisions → [stop here if mode = review] → plan → implement → test → done
```

`state.json` → `phase` is one of: `intent`, `research`, `decisions`, `awaiting-review`, `plan`, `implement`, `test`, `done`. Whoever moves a work to a new phase updates `phase` and `updated`.

## Mode

- **`review`**: stop when the decision map is finished and wait for the human.
- **`auto`**: keep going through plan and implementation without stopping (e.g. overnight).

The project default lives in `.pia/config.json`; each work has its own `mode` in `state.json`. The human switches it at any time (`/pia:auto`, `/pia:review`, or just saying so). **The lead reads `mode` from `state.json` at the moment the decision map is finished, not before**, so switching during research works.

## Keep-awake (caffeinate)

While agents work unattended, the machine must not sleep.

- **Start:** at the very beginning of every new work, and whenever a stopped work starts running again: run `caffeinate -dims` in the background and save its PID to `.pia/work/<id>/caffeinate.pid`.
- **Stop:** as soon as the work is waiting for the human or finished:
  - mode `review` → when the decision map is finished (phase `awaiting-review`);
  - mode `auto` → at the end of everything, when implementation is finished (phase `test`).
- Stop means: kill **only** the PID saved in that work's `caffeinate.pid`, only if that PID is still a `caffeinate` process, then delete the file. Never kill other `caffeinate` processes; another work may own them.

In Claude Code: `bash "<plugin>/scripts/awake.sh" start|stop|status .pia/work/<id>`.

## Team

| Role | Who | Writes |
|---|---|---|
| **Lead** | the session the human talks to | `state.json`, `intent.md`, messages to the human |
| **Researcher** | teammate `researcher-<NNN>` | `research.md`, `decisions.md`, lines in `DECISIONS.md` |
| **Reviewer** | teammate `reviewer-<NNN>` (a fresh one for the plan: `plan-reviewer-<NNN>`) | nothing, only messages |
| **Planner** | teammate `planner-<NNN>` | `plan.md` |
| **Implementer** | teammate `implementer-<NNN>` | code, check-offs in `plan.md` |

`<NNN>` is the work number. Every role writes to `log.md`.

- **How agents are spawned.** In Claude Code with agent teams enabled, the lead spawns each role as a teammate by calling the Agent tool with a `name`. Without agent teams, the same names spawn named subagents. Either way, agents talk only through `SendMessage`, addressing each other by name.
- **Spawn prompt.** Every teammate gets: its role, the work id and folder, the names of the agents it talks to, and the instruction to read this file first (sections *All agents*, *Team*, and its own phase sections) plus `CLAUDE.md`, `.pia/DECISIONS.md`, `state.json` and `intent.md`.
- **The lead keeps its context small.** It coordinates; it does not read `research.md` or `plan.md` end to end. Reviewers do that.
- **One writer per file.** Only the owner in the table above edits a file.
- **Replacement.** If a teammate fails, stops early, or runs out of context, the lead spawns a replacement with the same role and name suffix `-2`, `-3`… It resumes from the files and the `## Now` section of `log.md`.
- **Shutdown.** When a phase is finished, the lead asks the agents of that phase to shut down. The implementer stays alive through the test phase.

## All agents

1. Before working, read: `CLAUDE.md`, this file, `.pia/DECISIONS.md`, and your work's `state.json` and `intent.md`.
2. **📌 Binding decisions are never re-decided.** Other past decisions are the default unless there is a stated reason to deviate, and deviating is itself a new decision.
3. **Log as you go** in `log.md`: when you start, after each meaningful step, when something fails, and when you hand off. Keep the `## Now` section at the top current (phase, who is doing what, next step, blockers). Entries are short: `YYYY-MM-DD HH:MM · role · what happened`.
4. **After compaction or a restart**, before doing anything: re-read this file (*All agents* and your phase sections), `state.json`, and `## Now` in `log.md`.
5. **Only the lead talks to the human.** Anything else that would need a human answer becomes a decision: decide it and record it.
6. **Don't execute destructive or outward-facing actions** (force-push, pushing to a protected branch, deleting data, spending money, messaging people, deploying to production) unless `intent.md` or a decision explicitly authorizes it. Otherwise record it as a decision and leave the action for the human.
7. All PIA documents are written in **English**. The lead talks to the human in the human's language.

## Phase 1: Intent (lead + human)

**Don't assume the intention. Clarify it.** The questions prove the agent understands: *"How will I know the agent understands? When it asks me the right questions."*

1. Read the intention, `DECISIONS.md`, and enough of the code to ask good questions.
2. Ask **one numbered batch** of short questions in plain words: what exactly, why, for whom, what is in and out of scope, what "done" looks like, constraints, and anything you would otherwise have to guess. Give each question a suggested answer, so the human can reply "yes to all", answer only some, or say "you decide".
3. Ask a follow-up batch only if an answer opened something new. Don't ask what research can find out, and don't ask technical choices; those become decisions in Phase 3.
4. Write `intent.md`: short, readable, with the questions and answers at the bottom. Move to `research`.

## Phase 2: Research (researcher ⇄ reviewer)

`research.md` is **for agents**. Make it exhaustive: the more complete and coherent, the better every later agent works. Use the `research.md` template.

**Progressive disclosure.** Long documents stay readable for a human who wants to dig in: open with an *At a glance* section (10 lines at most), start every section with a one-line summary, and put deep detail inside `<details><summary>…</summary>` blocks, so it reads top-down and opens only where needed. The same applies to `plan.md`.

- Read the real code in the area **deeply**: trace the actual flow, don't skim.
- **Web research is mandatory** for every external library, framework, API, model or SDK in play: read the current docs, verify versions, cite URLs, flag anything deprecated or decaying.
- Include: current state, how it really works today, related components, data and flow, constraints, the 📌 Binding decisions that touch this area, relevant past decisions, edge cases, risks, and an index of key files.
- **No "Open Questions" section.** Every open point, fork or assumption becomes a decision in Phase 3.
- When done, send `READY FOR REVIEW: research.md` to the reviewer (see *Reviewing*).

## Phase 3: Decisions (researcher ⇄ reviewer)

`decisions.md` is **for the human**. Follow the `decisions.md` template exactly.

1. **List every decision the work needs** (architecture, where things run, data, behavior, libraries, failure cases, trade-offs) and every assumption you would otherwise make silently. *Everything written must be a decision.*
2. **Learn how the human thinks first.** Read `DECISIONS.md` (and past works' `decisions.md` when relevant). Recommend consistently with past choices and say so: *"Consistent with D-004."*
3. **Always decide.** The recommended option is the decision. Say why in one or two sentences.
4. **IDs are global and permanent.** Take the next number after the highest `D-NNN` in `DECISIONS.md`, and reserve it right away by appending its line there. Never reuse or renumber.
5. **Weight** every decision:
   - 🔴 **High:** hard to undo; changes architecture, data, cost or the experience broadly; or many things depend on it.
   - 🟡 **Medium:** affects one area; undoing it costs some rework.
   - 🟢 **Low:** local; cheap to change later.
6. **Order** High → Medium → Low. Fill the summary line at the top.
7. **Each card stands alone.** Write it for a reader who has read nothing else: a short context that says what is being built and why this decision exists, 2 to 4 options each with its consequence, the decision and its reason, what it depends on and what it affects. *Simple to read, deep at the same time.* Plain words; file paths only when essential.
8. Send `READY FOR REVIEW: decisions.md` to the reviewer.
9. When approved: make sure every decision has its line in `DECISIONS.md`, then tell the lead `DECISIONS DONE`.

**Lead, when decisions are done:** read `mode` from `state.json` now.
- `review` → set phase `awaiting-review`, **stop caffeinate**, shut down the researcher and reviewer, and send the human a short message: counts by weight, the titles of the 🔴 decisions, the path to `decisions.md`, and how to continue (change any decision by saying so or with `/pia:change`, then `/pia:continue`). Then stop.
- `auto` → set phase `plan`, shut down the researcher and reviewer, and go to Phase 4.

## Reviewing (reviewer)

The reviewer makes the work good before anyone relies on it. It is adversarial and concrete.

- **research.md:** verify claims against the real code and the web; hunt for missing areas, flows, edge cases, versions and risks. Nothing important may be missing.
- **decisions.md:** complete (every fork and assumption in `research.md` is a decision; nothing is silently assumed), coherent (no contradictions with each other, with 📌 Binding, or with the intent), well written (each card stands alone and is plain), weights sensible, recommendations justified and consistent with past decisions.
- **plan.md:** every decision is implemented by some step; steps are specific enough to execute mechanically; nothing contradicts a decision; tests are defined per phase.

Loop: reply to the author with **numbered findings**, or `APPROVED: <file>`. The author fixes and sends `READY FOR REVIEW` again. On approval, also message the lead `APPROVED: <file>`.

**The work must not stall.** After 5 rounds without approval, approve and turn each remaining disagreement into a decision (decided, with both positions in the options).

## Phase 4: Plan (planner ⇄ plan-reviewer)

`plan.md` is **for agents**: a literal to-do list built from `research.md` and `decisions.md`. Use the `plan.md` template, with progressive disclosure (see Phase 2).

- **No new decisions.** If one is truly missing, add a card to `decisions.md` (the researcher owns that file; if the researcher is gone, the planner may append it) with status `agent`, and tell the reviewer.
- A short **"How it works"** section: the behavior, step by step, as cause → effect.
- **Phases** with checkbox steps. Each step names the files it touches and the decision IDs it implements: `- [ ] 2.3 Render the PDF on the server [D-017]`.
- **Tests per phase** (what to run, what must pass).
- Send `READY FOR REVIEW: plan.md` to the plan-reviewer. When approved, the lead sets phase `implement`, shuts down the planner and plan-reviewer, and spawns the implementer.

## Phase 5: Implement (implementer)

- Follow `plan.md` step by step. Check off each step when done. Run the tests/typecheck at the end of each phase.
- **No stops in the middle.** The human may be asleep. If something blocks, decide how to proceed (a decision), log it, and keep going.
- Log every meaningful step and every failure in `log.md`.
- When everything is done, tell the lead `IMPLEMENTATION DONE` with: what was built (3 to 5 bullets), how to test it (short numbered steps), and what you could not verify yourself.

**Lead:** set phase `test`, **stop caffeinate**, and send the human that summary, short.

## Phase 6: Test (human ⇄ lead ⇄ implementer)

- The human tests and gives feedback to the lead. The lead forwards each item to the implementer (spawning a new one if it is gone).
- The implementer fixes each item and logs it under `## Test & fixes` in `log.md`: what failed, why it failed, the fix.
- Compaction keeps working as usual; the log is what makes long fix sessions possible.
- When the human says it's done: phase `done`, shut down the team.

## Changing a decision

When the human changes a decision (by saying so or with `/pia:change`):

1. Update the card: new decision and reason, `Status: changed`, and one history line: `Was: B (agent) · changed YYYY-MM-DD`.
2. Update its line in `DECISIONS.md`.
3. **Find the impact:** cards whose *Depends on* includes it, plan steps tagged with it, and implemented steps in `log.md`.
4. Tell the human the impact as a short list.
5. If the work is already planned or implemented, add a `## Change D-NNN` phase to `plan.md` for the affected steps. In `auto` mode implement it; in `review` mode wait for the human's go.

When the human continues a work after reviewing its map, every card still marked `agent` becomes `approved`.

## 📌 Binding decisions

The `📌 Binding` section of `DECISIONS.md` holds rules every work follows, in full text (projects that had a `docs/RULES.md` had it imported here). When a decision should hold for all future work, or the human keeps repeating the same instruction, the agent records a 🔴 decision proposing to promote it to Binding. Once decided, move its full text into the Binding section.

## Compaction

Auto-compaction is configured by `/pia:init` (`autoCompactWindow` in `.claude/settings.json`, from `config.json`). Nobody compacts by hand. After a compaction, a hook reminds the agent of its work's state and `## Now`; rule 4 of *All agents* still applies.
