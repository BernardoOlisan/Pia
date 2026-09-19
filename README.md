# PIA

**Decision Driven Development (DDD).** A good agentic system, given an intention, resources and context, should work for hours, even all night. Your attention goes only to the decisions.

PIA is a workflow for coding agents, packaged as a Claude Code plugin. You state an **intention**. Agents clarify it with you, then research, decide, plan and build, reviewing each other along the way. They write long, exhaustive documents for themselves. You read one thing: a **decision map**.

→ Why: [PHILOSOPHY.md](PHILOSOPHY.md)

## How it works

```
you: /pia:new <intention>
  │
  ├─ Intent      the lead asks you everything it needs to understand what you want
  ├─ Research    researcher ⇄ reviewer (both investigate), until nothing is missing   🤖 research.md
  ├─ Decisions   every choice becomes a decision, already decided                    👤 decisions.md
  │              ── mode "in-the-loop": stop here and wait for you
  ├─ Plan        planner ⇄ reviewer, a literal to-do list                            🤖 plan.md
  ├─ Implement   implementer builds it, logging as it goes                           🤖 logs/
  └─ Test        you test, give feedback, agents fix
```

- **Agents always decide.** Each decision comes with the recommended answer already chosen and the reason. You approve or change it. What you answer during the intent is recorded as decided by you.
- **Decisions have permanent IDs** (`D-017`) across the whole project. Change one later and PIA shows what depends on it.
- **Decisions have weight** (🔴 high, 🟡 medium, 🟢 low) and an area, so you read what matters first.
- **Decisions are memory.** New work reads past decisions to recommend the way you'd choose.
- **Nothing stops the work:** automatic compaction for the lead and every teammate, logs to resume from, replaceable agents.
- **The machine stays awake** (`caffeinate -dims`) while agents work unattended, and lets go when Claude Code closes.

## A decision

```markdown
### D-017 · Where is the PDF generated?  🔴 High

**Context:** Reports can be exported as PDF. The PDF can be drawn on the phone or on the server.

- **A) On the phone:** works offline, but each device renders it slightly differently
- **B) On the server:** identical everywhere, but needs a connection

**✅ Decided: B.** The report must look the same for every client. Consistent with D-004 (online-only).
**Area:** reports · **Depends on:** D-004 · **Affects:** plan phases 2 and 3
**Status:** agent
```

## Install

Requires Claude Code **2.1.270+** (agent teams; teammate auto-compaction verified on this version) and `python3`. Keep-awake uses macOS `caffeinate`, and is skipped where it isn't available.

```
/plugin marketplace add BernardoOlisan/Pia
/plugin install pia@pia
```

For local development, from a clone: `claude --plugin-dir /path/to/Pia`.

## Commands

| Command | What it does |
|---|---|
| `/pia:init` | Set up PIA in a repo: `.pia/`, import `docs/RULES.md` as 📌 Binding decisions, point `CLAUDE.md` at PIA, enable auto-compaction (600k tokens) and agent teams. Restart Claude Code afterwards. |
| `/pia:new <intention>` | Start a work. Keeps the machine awake, clarifies the intention, runs the team. |
| `/pia:new --voice` | Same, but you say the intention and answer the questions by talking (macOS, notch, GPT-Live). See [voice/](voice/IDEAS.md). |
| `/pia:transcribe` or **⌥Space** | Just dictation, no PIA: the island records until you click it (or press ⌥Space again), `gpt-transcribe` writes it, and the text is copied to your clipboard. Never reaches Claude. |
| `/pia:status` | Where every work stands. |
| `/pia:continue [work]` | Resume a work after reviewing its decisions, or in a new session. |
| `/pia:change D-017 <answer>` | Change a decision and see its impact. |
| `/pia:in-the-loop [work]` | Stop at the decision map and wait for you (default). |
| `/pia:out-of-the-loop [work]` | Don't stop; go all the way to implementation. `--default` on either changes the project default. |
| `/pia:compact <tokens>` | Change the auto-compaction window, e.g. `600k`. |

### The island

While you dictate, the island in the notch draws what Voice Memos draws: the live waveform on one side, the elapsed time on the other, both in red. On a screen with no notch — an external monitor — it floats as a full pill instead, and it follows you across screens and across Desktops.

- **One click** stops the take. So does ⌥Space.
- **Two clicks** show this month's cost beside the waveform, as a quiet white hint; two more hide it again. It is hidden by default.

### Dictation cost

Dictation costs $0.0045 per minute (`gpt-transcribe`). The total starts again at `$0.000` every month. To reset it sooner, stop the dictation process and delete its ledger:

```
pkill -f "pia-voice dictate serve"; rm -f ~/Library/Application\ Support/PIA\ Voice/dictation.json
```

The process keeps the total in memory, so deleting the file alone isn't enough. It starts again with Claude Code, or right away (already recording) with `/pia:transcribe`. As an alias, in `~/.zshrc`:

```
alias pia-transcribe-reset='pkill -f "pia-voice dictate serve"; rm -f ~/Library/Application\ Support/PIA\ Voice/dictation.json && echo "PIA Transcribe: cost reset to \$0.000"'
```

## In your project

```
.pia/
├── PIA.md            how agents work here (source of truth, readable by any agent)
├── DECISIONS.md      📌 Binding decisions + one line per decision ever made
├── config.json       default mode, compaction window
└── work/003-export-pdf/
    ├── state.json    phase, mode
    ├── intent.md     👤
    ├── research.md   🤖
    ├── decisions.md  👤
    ├── plan.md       🤖
    ├── log.md        🤖 the lead's summary
    └── logs/         🤖 one log per agent
```

👤 for you · 🤖 for agents

## Notes

- **Unattended runs:** teammate permission prompts appear in the lead's session and would wait for you. For overnight work, run Claude Code in a permission mode that won't block, e.g. `claude --permission-mode auto`.
- **Other sessions** in a PIA project compact normally at the same window, with nothing from PIA injected.
- **Several works at once:** fine up to the plan; only one work implements at a time.
- **Logs keep real time:** agents log through `scripts/log.sh`, which stamps the machine's clock and refreshes `## Now` on every entry.
- **Interrupting or restarting Claude Code** stops in-process teammates. PIA picks up from the logs; Claude Code asks you before a stopped agent is replaced.
- **Agent teams are experimental** in Claude Code. If they're off, PIA runs the same roles as named subagents.
- Status: early. Built in the open; expect changes.
