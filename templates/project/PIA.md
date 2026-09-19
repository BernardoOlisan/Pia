# PIA: Decision Driven Development

This file is the **source of truth** for how agents work in this repository. Any coding agent can read it and follow it. In Claude Code, the `pia` plugin exposes it as `/pia:*` commands.

It is owned by the plugin and refreshed by `/pia:init`. Don't edit it by hand. Anything specific to this project belongs in `.pia/DECISIONS.md`.

## The idea in one minute

- **PIA only does what a session can't do by itself:** memory across works, continuity after a compaction, autonomy while the human is away, and the map the human reads when they come back. How to investigate, how to plan the steps and how to write the code is left to the model.
- Long, exhaustive documents are for agents. The human reads a **decision map**.
- **Everything written is a decision.** The human reviews the decisions that govern the work, not the work itself.
- **Agents always decide.** The recommended answer *is* the decision, with its reason. The human can change any decision at any time, and the system works out what depends on it.
- **The work never stops** because the human is away or an agent ran out of context: logs, a reviewer, replacements and automatic compaction keep it going.
- **Decisions become memory.** Past decisions shape future recommendations.

## Layout

```
.pia/
├── PIA.md                 this file
├── DECISIONS.md           project memory: 📌 Binding decisions (full text) + one line per decision
├── config.json            project defaults: mode, auto-compact window (tokens)
├── .gitignore             ignores *.pid and the ID lock
└── work/<NNN-slug>/       one folder per intention (feature, fix, anything)
    ├── state.json         id, title, mode, phase, lead session
    ├── talk.md            👤 the conversation: the intention, what was found, what the human decided
    ├── research.md        🤖 exhaustive research, written while the talk is happening
    ├── decisions.md       👤 the decision map
    ├── log.md             🤖 the lead's summary log, with "## Now" at the top
    ├── logs/<agent>.md    🤖 one log per agent (scout-004.md, scout-reviewer-004.md, …)
    └── caffeinate.pid     temporary, never committed
```

👤 written for the human. 🤖 written for agents only; the human never has to read it.

## Phases

```
talk → decisions → [stop here if mode = in-the-loop] → implement → test → done
```

`state.json` → `phase` is one of: `talk`, `decisions`, `awaiting-review`, `implement`, `test`, `done`. Whoever moves a work to a new phase updates `phase` and `updated`.

**There is no plan phase and no plan document.** The implementer works out its own steps from the decision map and the research, and keeps them as a short checklist in its log. A model plans its own work well; a separate planning stage only restates what is already written.

## Mode

- **`in-the-loop`** (default): the human stays in the loop. Stop when the decision map is finished and wait for the human.
- **`out-of-the-loop`**: keep going through implementation without stopping (e.g. overnight). The human reviews the decisions afterwards.

The project default lives in `.pia/config.json`; each work has its own `mode` in `state.json`. The human switches it at any time (`/pia:in-the-loop`, `/pia:out-of-the-loop`, or just saying so), including in the middle of the talk, and `/pia:new` takes `--out-of-the-loop` to start that way.

**The lead checks `mode` before every question it would put to the human**, not once at the end. The talk is where the human is needed most, so the talk is where a switch has to take effect; a lead that only reads the mode later keeps asking an empty chair.

## Keep-awake (caffeinate)

While agents work unattended, the machine must not sleep.

- **Start:** at the very beginning of every new work, and whenever a stopped work starts running again: run `caffeinate -dims` in the background and save its PID to `.pia/work/<id>/caffeinate.pid`. In Claude Code it also watches the Claude process (`-w`), so it exits by itself if Claude closes or crashes.
- **Stop:** as soon as the work is waiting for the human or finished:
  - mode `in-the-loop` → when the decision map is finished (phase `awaiting-review`);
  - mode `out-of-the-loop` → at the end of everything, when implementation is finished (phase `test`);
  - any mode → when the work has to wait (see *Works in parallel*), or when the lead's session ends.
- Stop means: kill **only** the PID saved in that work's `caffeinate.pid`, only if that PID is still a `caffeinate` process, then delete the file. Never kill other `caffeinate` processes; another work may own them.

In Claude Code: `bash "<plugin>/scripts/awake.sh" start|stop|status .pia/work/<id>`.

## Team

| Role | Who | Writes |
|---|---|---|
| **Lead** | the session the human talks to | `state.json`, `talk.md`, `log.md`, messages to the human |
| **Scout** | teammate `scout-<NNN>` | `research.md`, `decisions.md`, lines in `DECISIONS.md` |
| **Scout reviewer** | teammate `scout-reviewer-<NNN>` | nothing but its own log and messages |
| **Implementer** | teammate `implementer-<NNN>`; a fresh `implementer-<NNN>-2`, `-3`… for each round of test feedback | code, its own step checklist |

`<NNN>` is the work number. Every agent also writes its own `logs/<its name>.md`.

- **How agents are spawned.** In Claude Code with agent teams enabled, the lead spawns each role as a teammate by calling the Agent tool with a `name`. Without agent teams, the same names spawn named subagents. Either way, agents talk only through `SendMessage`, addressing each other by name.
- **Spawn prompt.** Every teammate gets: its role, the work id and folder, the names of the agents it talks to, the paths of the log script and the decision ID script, and the instruction to read this file first (sections *All agents*, *Team*, and its own phase sections) plus `AGENTS.md`, `.pia/DECISIONS.md`, `state.json` and `talk.md`.
- **The lead keeps its context small.** It coordinates; it does not read `research.md` end to end. It asks the scout and gets short answers.
- **One writer per file.** Only the owner in the table above edits a file.
- **Replacement.** If a teammate fails, stops early, or runs out of context, the lead spawns a replacement with the same role and name suffix `-2`, `-3`… It resumes from the files, the `## Now` of `log.md`, and the log of the agent it replaces. If Claude Code says the human stopped that agent (for example by interrupting or restarting Claude Code), ask the human in one line before replacing it: Claude Code requires that.
- **Shutdown.** When a phase is finished, the lead asks the agents of that phase to shut down. The implementer shuts down at `IMPLEMENTATION DONE`; test feedback goes to a fresh one (Phase 4).

## All agents

1. Before working, read: `AGENTS.md`, this file, `state.json` and `talk.md`, and from `.pia/DECISIONS.md`: the **📌 Binding** section in full, plus the lines of *All decisions* for the areas your work touches (search by `[area]`; don't read the whole list).
2. **📌 Binding decisions are never re-decided.** Other past decisions are the default unless there is a stated reason to deviate, and deviating is itself a new decision.
3. **Log with the log script, never by hand**, in your own file `logs/<your name>.md`:
   `bash "<plugin>/scripts/log.sh" <your log> "<what happened>" --doing "<what you're doing now>" [--next "…"] [--blockers "…"]`
   It stamps the real time and rewrites your `## Now` in the same step, so times are never guessed and `## Now` never goes stale. Log when you start, after each meaningful step, when something fails, every `READY FOR REVIEW`, findings, `APPROVED` or report you send or receive, and when you hand off. The implementer logs at least at the start and the end of every step group. Keep entries short. Only the lead writes `log.md` (it also passes `--phase` and `--team`). Any other time you write (`state.json`, history lines) comes from `date '+%Y-%m-%d %H:%M'`. Without the script: take the time from the machine clock and update `## Now` with every entry.
4. **After compaction or a restart**, before doing anything: re-read this file (*All agents* and your phase sections), `state.json`, the `## Now` of `log.md`, and your own log. Re-read **only those parts** (ranged reads, or search for the section), not whole documents: re-reading everything after every compaction fills the context again and can make compaction loop.
5. **Only the lead talks to the human.** Anything else that would need a human answer becomes a decision: decide it and record it.
6. **Don't execute destructive or outward-facing actions** (force-push, pushing to a protected branch, deleting data, spending money, messaging people, deploying to production) unless `talk.md` or a decision explicitly authorizes it. Otherwise record it as a decision and leave the action for the human.
7. All PIA documents are written in **English**. The lead talks to the human in the human's language.
8. **Images fill the context fast.** Shrink screenshots before reading them (on macOS: `sips -Z 1000 <file>`), and don't read the same image twice.

## Writing for the human

Everything the human reads (the talk, `talk.md`, `decisions.md`, messages from the lead) is written to be understood without effort:

- **Plain words and short sentences.** One idea per sentence.
- **Teach, don't show off.** When a technical term is needed, explain it in a few words the first time.
- **Fewer words, same depth.** Cut what the reader doesn't need to decide. A long paragraph is a sign the idea isn't clear yet.
- **Lead with the point**, then the reason.
- **No code names or file paths** unless the human needs them to act.

## Phase 1: The talk (lead + human, scout underneath)

One conversation that is the intention **and** the research at the same time. Not rounds of questions. The human says what they want; the lead investigates while they talk, and asks only what it can't find out on its own.

*"How will I know the agent understands? When it asks me the right questions."* A question worth asking almost always depends on something the agent found. That is why the investigation runs during the talk and not after it.

**Start the scout immediately.** The moment the work exists — before the first question — the lead spawns `scout-<NNN>` with whatever the human has already said, even if it is one line. The human never talks to it.

**How the lead talks:**

1. **One or two questions at a time**, in the human's language, like a colleague. No numbered rounds, no batches of eight. If an answer opens three new questions, ask the one that most changes the work and hold the rest.
2. **Ask only what investigation can't answer.** Anything the scout can find out, the scout finds out. What's left is what only the human knows: the outcome and why, who it's for, what "done" looks like, what is in and out of scope, constraints, preferences, and which side of a real fork they want.
3. **Ask informed.** Say what was found when it changes the question: *"Today everything goes straight to the API with no cache, so 'offline' means one of two very different things…"*. This is not diagnosing for the human; it is handing them a fork instead of a blank page.
4. **Feed the scout as the talk moves.** Send it, in one line, what to look at next, and ask it direct questions. It answers in two or three lines, never with a document.
5. **Never read `research.md`.** That is how the lead's context stays small however long the talk runs.
6. **The human investigates too.** A link, an article or an idea the human brings goes into the talk, and the scout verifies it.
7. **The human can change their mind at any point.** Keep the intention in `talk.md` at its latest version, not its first.

**Decisions the human makes here.** When the human settles something that is really a decision (a technology, a behaviour, a trade-off), record it in `talk.md` under *Decided by you*. In Phase 2 it becomes a card with `Status: human`, and nobody re-decides it. The heaviest decisions are the best ones to settle here, while the human is present.

**How the talk ends.** When the lead could explain the work back without guessing anything, it does exactly that: a short summary of what it understood — the intention, the scope, what matters most — and asks the human to confirm. Not more questions about details: a demonstration of understanding. If the human corrects it, or thinks of something new right after it, the talk simply carries on. **The talk is never closed**: test feedback lands in it too (Phase 4).

### When the human isn't there (mode `out-of-the-loop`)

*"What happens when the boss isn't there? The agents decide."*

- **From the start:** ask the human nothing at all. Talk to the scout instead, and make every question you would have asked into a decision of your own. A mode that sometimes stops is not a mode: never wait, and never ask whether they are still there.
- **Switched mid-talk** (the usual case: *"I'm going to sleep"*): stop asking at once. Take the questions they left unanswered **and the ones you were still going to ask**, and turn each into a decision with its answer and its reason. Then end the talk yourself: write into `talk.md` the summary you would have demonstrated, saying plainly that they did not confirm it. Set phase `decisions` and carry on.
- **A question they never answered outranks an ordinary decision**, because you judged it worth their time. Its card carries the line `Asked you during the talk; you were away.`, and every report you send them afterwards lists those cards **first**, ahead of the 🔴 ones. Otherwise the one thing they cared about is buried among twenty others.

**Write `talk.md` as the talk goes**, not at the end, using the `talk.md` template. Then set phase `decisions`.

**By voice** (optional, `/pia:new --voice` in Claude Code on macOS): the same talk, out loud. You are still the brain — you read the code, ask the scout and decide what to say. `pia-voice` is your mouth and your ears, and it has no opinions of its own.

- **How it works.** The voice passes on what the human said as a `PIA-VOICE SAID` line. You answer by appending **one line at a time** to `logs/voice-inbox.txt` in the work folder, and the voice says it in its own words. No rounds and no forms: write when you have something, exactly as you would type it.
- **Write to be heard.** Everything you append is going to be spoken, so *Writing for the human* holds, plus three rules that only matter out loud: no lists or headings, because a bullet can't be heard; never a file path, a decision ID or a code name; and as long as the idea needs, but in pieces, so the human can interrupt.
- **The island is the switch.** A session bills by the second, silence included, so it closes itself after a stretch of quiet and **speaking never reopens it**. One click on the island, or ⌥V, wakes it or puts it to sleep; two clicks show the cost, as in dictation.
- **When you have something and the island is asleep**, the voice wakes and says it. Started with `--notify`, the island's dot turns blue and chimes once instead, and nothing is billed until the human wakes it. They can switch either way by saying so.
- **`PIA-VOICE ENDED` means the voice stopped, not that the human left.** Unless they clearly said they are going away, the work stays `in-the-loop`: carry on in the terminal, writing normally. Out-of-the-loop is never inferred (see *When the human isn't there*).
- The conversation is kept in `logs/voice.md`. You write `talk.md` exactly as in the typed talk.

## Phase 2: Research and decisions (scout ⇄ scout-reviewer)

`research.md` is **for agents**. It is written during the talk, not after it, and it is exhaustive: the more complete and coherent, the better every later agent works. Use the `research.md` template.

**Progressive disclosure.** Long documents stay readable for a human who wants to dig in: open with an *At a glance* section (10 lines at most), start every section with a one-line summary, and put deep detail inside `<details><summary>…</summary>` blocks.

- Read the real code in the area **deeply**: trace the actual flow, don't skim.
- **Web research is mandatory** for every external library, framework, API, model or SDK in play: read the current docs, verify versions, cite URLs, flag anything deprecated or decaying.
- Include: current state, how it really works today, related components, data and flow, constraints, the 📌 Binding decisions that touch this area, relevant past decisions, edge cases, risks, and an index of key files.
- **No "Open Questions" section.** Every open point, fork or assumption becomes a decision.

Then write `decisions.md`, which is **for the human**. Follow the `decisions.md` template exactly, and *Writing for the human*.

1. **List every decision the work needs** (architecture, where things run, data, behaviour, libraries, failure cases, trade-offs) and every assumption you would otherwise make silently. *Everything written must be a decision.*
2. **Learn how the human thinks first.** Read the lines of `DECISIONS.md` for the areas this work touches (and past works' `decisions.md` when relevant). Recommend consistently with past choices and say so: *"Consistent with D-004."*
3. **Always decide.** The recommended option is the decision. Say why in one or two sentences. Decisions the human already made in the talk keep the human's answer, with `Status: human`. A card that replaced a question the human never got to answer says so on its own line: `Asked you during the talk; you were away.`
4. **IDs are global and permanent.** Reserve them with the decision ID script (`next-decision-id.sh <project root> <work id> <count>`): it takes a lock, so two works never get the same number, and appends `⏳ reserved` lines to `DECISIONS.md`. Replace each reserved line with the real one when its card is written. Without the script: take the next number after the highest `D-NNN` in `.pia/` and append its line right away. Never reuse or renumber.
5. **Area:** give every decision a short lowercase area (`reports`, `auth`, `sync`…). Reuse existing areas from `DECISIONS.md` before inventing one.
6. **Weight** every decision:
   - 🔴 **High:** hard to undo; changes architecture, data, cost or the experience broadly; or many things depend on it.
   - 🟡 **Medium:** affects one area; undoing it costs some rework.
   - 🟢 **Low:** local; cheap to change later.
7. **Order** High → Medium → Low. Fill the summary line at the top.
8. **Each card stands alone, and is short.** Write it for a reader who has read nothing else: a context of at most 3 short sentences, 2 to 4 options with their consequence in one line each, the decision and its reason in one or two sentences, its area, what it depends on and what it affects. Detail that doesn't fit belongs in `research.md`.
9. Send `READY FOR REVIEW` to the scout reviewer, naming both files.
10. When approved: make sure every decision has its final line in `DECISIONS.md` (`D-NNN  weight  [area] what was decided · work/<id> · status`, no `⏳` left), then tell the lead `DECISIONS DONE`.

**Lead, when decisions are done:** read `mode` from `state.json` now.
- `in-the-loop` → set phase `awaiting-review`, **stop caffeinate**, shut down the scout and its reviewer, and send the human a short message: first the titles of any cards that say *you were away*, then counts by weight, the titles of the 🔴 decisions, the path to `decisions.md`, and how to continue (change any decision by saying so or with `/pia:change`, then `/pia:continue`). Then stop.
- `out-of-the-loop` → set phase `implement`, shut down the scout and its reviewer, and go to Phase 3.

## Reviewing (scout reviewer)

One reviewer, one pass over both files. It doesn't just check the documents: **it investigates on its own**, in the code and on the web, to confirm the facts and to find what is missing. It is adversarial and concrete, and it reviews **substance, not prose**.

- **research.md:** independently trace the flows in the real code and read the current external docs; confirm or refute each claim; hunt for missing areas, flows, edge cases, versions and risks. Nothing important may be missing. *(This is where the reviewer earns its keep: a claim nobody checked becomes a decision built on sand.)*
- **decisions.md:** complete (every fork and assumption found by you or the scout is a decision; nothing is silently assumed), coherent (no contradictions with each other, with 📌 Binding, with the talk, or with decisions the human made in it), weights and areas sensible, recommendations justified and consistent with past decisions.
- **Not a finding:** wording, tone, or a card you would have phrased differently. *Writing for the human* is the author's job, not a review round.

Loop: reply to the scout with **numbered findings** (each with the evidence you found), or `APPROVED`. The scout fixes and sends `READY FOR REVIEW` again. On approval, also message the lead `APPROVED`.

**Messages can get lost** (for example while an agent is compacting). So nobody waits blindly:
- Both sides log every `READY FOR REVIEW`, findings and `APPROVED` they send or receive.
- **Reviewer:** after a compaction or when you go idle, check the files yourself. If a document you're waiting for exists and changed since your last review, review it without waiting for the message.
- **Scout:** if you're waiting for the reviewer and nothing arrives, send `READY FOR REVIEW` again and tell the lead.
- **Lead:** if both are idle and nothing moved, it's a deadlock: nudge both with what each is waiting for, and log it.

**The work must not stall.** After 3 rounds without approval, approve and turn each remaining disagreement into a decision (decided, with both positions in the options).

## Phase 3: Implement (implementer)

The implementer plans its own work. There is no plan document to follow.

1. Read `decisions.md` and `research.md`, and write a **short checklist** under `## Steps` at the top of your own log: one line per step, each naming the decision IDs it implements, e.g. `- [ ] 2 Render the PDF on the server [D-017]`. Keep it to the steps that matter, not every file edit. Every decision must be implemented by some step.
2. Build it, checking off each step as you finish it, and running the tests/typecheck for the part you just changed.
3. **No stops in the middle.** The human may be asleep. If something blocks, decide how to proceed (a decision), log it, and keep going.
4. **No new decisions quietly.** If a real fork appears that no card covers, decide it, append the card with `Status: agent` and its line in `DECISIONS.md`, and log it so the human sees it in the map.
5. **After each step**, send the lead `STEP DONE <n> of <total>: <one line>`. The lead logs it, so its `## Now` shows real progress.
6. When everything is done, tell the lead `IMPLEMENTATION DONE` with: what was built (3 to 5 bullets), how to test it (short numbered steps), and what you could not verify yourself.

**Lead:** set phase `test`, **stop caffeinate**, shut down the implementer, and send the human that summary, short. If the work ran `out-of-the-loop`, open with the cards that say *you were away*: those are the questions you would have put to them.

## Phase 4: Test (human ⇄ lead ⇄ implementer)

- The human tests and gives feedback to the lead. **The feedback is more of the talk:** the lead appends it to `## The conversation` in `talk.md`, in order, with its date. It does not go anywhere else and it is not a new round of anything.
- **If feedback contradicts a decision**, the lead first records it as a changed decision (see *Changing a decision*); the human's feedback counts as the go.
- **Each round of feedback gets a fresh implementer** (`implementer-<NNN>-2`, then `-3`…), with the round's items in its spawn prompt. It resumes from `decisions.md`, the latest part of `talk.md`, and the previous implementer's log and checklist, so it starts with a clean context. Later items from the same round go to it by message. Start caffeinate while it works and stop it when it reports.
- The implementer fixes each item (a failing test first, then the code), logs each fix with the log script (what failed, why it failed, the fix), and tells the lead `FIXES DONE` with the same short summary as `IMPLEMENTATION DONE`. Then the lead shuts it down.
- **Open questions before closing.** Whenever the lead asks the human about a decision, it logs `ASKED D-NNN: <question>`, and `ANSWERED D-NNN` when the human answers. Before setting `done`, the lead lists every question still unanswered and asks once more. If the human closes without answering, those cards keep the agent's decision.
- When the human says it's done: **mark every card still `Status: agent` as `approved`** (in `decisions.md` and `DECISIONS.md`), set phase `done`, and shut down the team.

## Approving the map

A card written by an agent is `agent` until the human has had the chance to see it. It becomes `approved` when:

- the human continues a work that was waiting at `awaiting-review` (`/pia:continue`, `/pia:out-of-the-loop`, or just saying go); or
- the human closes the work as `done`, whatever the mode.

**This applies to `out-of-the-loop` too.** Those works never pass through `awaiting-review`, so their cards would otherwise stay `agent` for ever and the map would never say what the human has actually seen.

## Changing a decision

When the human changes a decision (by saying so or with `/pia:change`), the lead does it:

1. Update the card: new decision and reason, `Status: changed`, and one history line: `Was: B (agent) · changed YYYY-MM-DD`.
2. Update its line in `DECISIONS.md`.
3. **Find the impact:** cards whose *Depends on* includes it, steps tagged with it in the implementer's checklist, and implemented steps in the logs.
4. Tell the human the impact as a short list.
5. If the work is already implemented, the change goes to an implementer as a round of test feedback (Phase 4). In `out-of-the-loop` mode start it; in `in-the-loop` mode wait for the human's go.

## Constraints the human changes mid-flight

When the human reverses or adds a constraint that governs the work ("don't commit anything" → "commit and push", "no new libraries after all"), that is a decision, not a passing remark. The lead records it as a card like any other — ID, weight, area, `Status: human` — or changes the existing card if one covers it. Otherwise the instruction lives only in the chat, and the next agent, or the next compaction, never sees it.

## 📌 Binding decisions

The `📌 Binding` section of `DECISIONS.md` holds rules every work follows, in full text (projects that had a `docs/RULES.md` had it imported here). When a decision should hold for all future work, or the human keeps repeating the same instruction, the agent records a 🔴 decision proposing to promote it to Binding. Once decided, move its full text into the Binding section.

## Works in parallel

Several works can run at the same time, each with its own lead session, folder and caffeinate.

- **Talking and deciding in parallel is fine.** Decision IDs never collide thanks to the ID script.
- **Only one work implements at a time.** Before moving to `implement`, the lead checks the other works' `state.json`. If another work is in `implement`, this work stays in `decisions` with a blocker in `## Now` ("waiting for work NNN to finish implementing"), **stops caffeinate**, and tells the human. It continues with `/pia:continue` once the other work reaches `test` or `done`.

## Compaction

Auto-compaction is configured by `/pia:init` (`autoCompactWindow` in `.claude/settings.json`, from `config.json`, default 600000 tokens). Nobody has to compact by hand, though the lead can run `/compact` any time.

After a compaction, a hook reminds the agent where its work stands, but **only in PIA sessions**: the lead of a work and that lead's teammates. Any other session in the project compacts normally, with nothing injected. Rule 4 of *All agents* still applies.

Teammate compaction was verified on Claude Code 2.1.270. On 2.1.260, one implementer grew past the window without compacting, so keep Claude Code up to date. Short-lived agents help too: that is why test feedback gets a fresh implementer, and why images are shrunk before reading.
