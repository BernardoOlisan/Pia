# PIA Voice: ideas (not built yet)

> **Voice as a companion in the moments where the human has to pay attention.**

Voice is an optional feature, not the core. PIA works exactly the same without it. The `.pia/` files are the interface: voice reads them, and only the Lead (Claude Code) writes them.

Status: feature 1 is built (`/pia:new --voice`, Swift package in this folder). Features 2 and 3 are written down so they aren't lost.

Also built, apart from PIA: **dictation** (`/pia:transcribe` or ⌥Space). `pia-voice dictate serve` runs while Claude Code is open (started by a SessionStart hook), records to .m4a, transcribes with `gpt-transcribe` ($0.0045/min) and copies the text to the clipboard. The notch shows a red dot while recording and this month's cost. A `UserPromptExpansion` hook blocks `/pia:transcribe` with exit 2, so Claude never sees it. Change the shortcut with `PIA_TRANSCRIBE_HOTKEY` (e.g. `ctrl+shift+d`, or `off`). Files: `~/Library/Application Support/PIA Voice/`. The cost resets every month; to reset it sooner, see *Dictation cost* in the README (alias `pia-transcribe-reset`).

**Setup:** save the OpenAI key in the Keychain (`security add-generic-password -s pia-voice -a openai -w`; `OPENAI_API_KEY` also works). The binary is built on first use with `swift build -c release --package-path voice`. Needs macOS 26.

## The pieces

| Piece | Role |
|---|---|
| **GPT-Live-1** (OpenAI) | Ears and mouth. Full-duplex conversation: listens while it speaks, handles interruptions and noise. Spanish, and Spanglish, welcome. |
| **Backend model** (OpenAI, via *Responses delegation*) | The brain behind the voice in feature 1. OpenAI runs it with the conversation context; we only give it tools. GPT-5.6 Terra, or GPT-5.6 Luna to save cost. |
| **Gemma 4 on Cerebras** | Candidate brain for feature 2 (client delegation). Not used in feature 1. |
| **pia-voice** (Swift, macOS) | Microphone, local VAD, the WebSocket to GPT-Live, runs the tools, and draws the notch. |
| **The bridge to Claude Code** | pia-voice runs in the background, started by the Lead; every line it prints reaches the Lead as an event. |

## Facts to keep in mind

- **GPT-Live-1** costs $0.05 per minute, billed per second, and **silence is billed too**: "time when the user speaks, the assistant speaks, both are silent, or the backend is working" ([cost guide](https://developers.openai.com/api/docs/guides/voice-latency-cost)). Backend models are billed separately.
- It takes audio and text only, with no images in or out.
- Context: 128k tokens. Startup instructions up to 16,384 tokens. A new session can start with up to 8,192 tokens of history (`input`, up to 128 messages). Each mid-session append is limited to 500 tokens ([sessions](https://developers.openai.com/api/docs/guides/live-conversations), [delegation](https://developers.openai.com/api/docs/guides/live-delegation)).
- **Responses delegation**: OpenAI backend models only. Tools are `function` definitions and `web_search`. A function call reaches the client as `response.output_item.done` (`call_id`, `name`, `arguments`); the client answers with `response.item.create` (`function_call_output`) and then `response.create`.
- **Voice and backend work run independently**: the backend can search the web while the user keeps talking.
- **The client can push context at any time**: `session.thinking.append` (known, not spoken), `session.commentary.append` (spoken, paraphrased) and `session.instructions.append`, with `delegation_id: null` when there is no delegation.
- **The assistant can speak first**: send `session.instructions.append` with what to say and keep input audio running, silence included.
- `session.usage.updated` reports the cumulative voice duration in seconds.
- **Client delegation** (for feature 2) works with any backend, but GPT-Live then calls no tools: it only emits `session.delegation.created` with no task text, and the client works out the task from the transcript.
- **Gemma 4 31B on Cerebras**: 131k context, tool calling, about 2,300 tokens per second, image input ([Cerebras](https://www.cerebras.ai/blog/first-look-gemma-4-on-cerebras-3-fast-multimodal-apps-we-built)).

**Cost, from feature 1 onward:** listen locally with an on-device voice activity detector (free), open a GPT-Live session only when you start talking, and close it after about 20 seconds of silence. A new session picks up the recent conversation, so it still feels "always on".

---

## 1. The intent, by voice (first)

`/pia:new --voice`: the **whole intent phase is a conversation**. You say the intention and answer the clarification questions, all by talking. Nothing typed.

**What the human thinks:**
- Dictation already beats typing because thinking is faster than writing; this makes it a conversation.
- **Claude still thinks the good questions**, because it has read the code. The voice asks them conversationally.
- You can also **just talk**: ask about your own intent, think out loud, have it search the web ("Stripe or Paddle?"), even while Claude is preparing questions.
- Claude writes `intent.md`. Voice never writes to `.pia/`.

### How it works

1. **Start.** The Lead creates the work folder, starts caffeinate, and runs `pia-voice intent .pia/work/<id>` in the background, watching its output. The notch appears.
2. **You talk.** The VAD hears you, pia-voice opens a GPT-Live session (Responses delegation, our tools plus `web_search`) and streams the audio, including the second before you started so no words are lost.
3. **Notes.** The backend model has the whole conversation in context; **its tool arguments are the notes**. When the intention is clear it calls `send_intent`, and pia-voice prints it for the Lead.
4. **Claude asks.** The Lead reads the code and writes `### Round 1` in `intent.md`, with suggested answers. pia-voice watches the file.
5. **The voice tells you.** pia-voice pushes a short notice with `session.thinking.append`. The voice doesn't interrupt; when you finish what you're saying it tells you "Claude's questions are here, shall we?". Then it calls `check_questions` for the full round and asks one by one. You can answer, discuss, or say "whatever it recommends".
6. **Answers.** At the end of the round it calls `send_answers`; the Lead records them in `intent.md` (human decisions under "Decided by the human") and decides whether there is another round.
7. **Confirm.** When the intent is clear, the Lead writes the final `intent.md`, the voice reads you a short summary, you confirm, it calls `confirm_intent`. The Lead moves to research, pia-voice exits, the notch disappears.

**While you wait** for Claude's questions there is no filler: talk if you want, or stay quiet and the session closes. **If the session is closed when questions arrive**, pia-voice opens it on its own and the voice tells you (no chime). You can also ask "are they here yet?" and it calls `check_questions`.

### Tools (backend model)

| Tool | What pia-voice does |
|---|---|
| `send_intent(intention, why, done_looks_like, scope, constraints)` | Prints it for the Lead. Called again if something changes. |
| `check_questions()` | Reads `intent.md` and returns the new round, or "not yet". |
| `send_answers(round, answers[])` | Prints the answers; each one says whether it was a human decision. |
| `confirm_intent()` | Tells the Lead you confirmed, then exits. |
| `end_voice()` | You said you don't want voice anymore: see *Ending early*. |
| `web_search` | Built in. |

Lines printed for the Lead: `PIA-VOICE INTENT {…}`, `PIA-VOICE ANSWERS R1 {…}`, `PIA-VOICE CONFIRMED`, `PIA-VOICE ENDED {…}`.

### When it ends

- **On its own:** when you confirm the intent (the phase changes to research).
- **If the Claude session closes:** pia-voice watches `CLAUDE_PID`, like caffeinate, and exits.
- **Ending early, or switching to no voice** mid-intent, three ways:
  1. Say it ("no more voice", "I'll type"): the model calls `end_voice`.
  2. Type it in the terminal: the Lead stops pia-voice.
  3. Click the dot in the notch.

  Nothing is lost: pia-voice sends what it has so far (intent and answers) and prints `PIA-VOICE ENDED`, the session closes, the notch disappears, and the Lead continues the intent in the terminal from the same round. The full conversation stays in `logs/voice.md`.

### The notch

Taken from the old Pia's UI (`~/Desktop/lab/pia/Sources/PiaUI`, **not** P1), and only these pieces:

- **The shape** (`IslandShape`, `NotchGeometry`): the black merges into the notch.
- **Left: the dot** (`AttentionLight`). Connected (GPT-Live session open): solid white with a glow. Not connected: a hollow ring breathing in low opacity.
- **Next to the dot: the cost so far**, just the number: `$0.00`. Voice time from `session.usage.updated` at $0.05/min, plus backend tokens if the events report them (to check). It adds up across sessions for this work.
- **Right: the voice level** (`VoiceMeter`): five bars with the real volume, brighter when the voice speaks, resting and breathing when not connected.
- **Speaking pulse** (the `pulse` in `IslandStates`): while the voice speaks the notch grows a little (10 pt per side, 8 pt down) with the volume, on a short spring.
- **Always visible** while pia-voice runs, even when not connected, so you know it's alive. No cards, no text, no questions on screen.

### Two prompts

Confirmed in the docs: the voice and the backend model get **separate prompts**.

- **GPT-Live**: `instructions` in `session.start`. How the voice talks.
- **Backend model**: `delegation.responses.instructions`. How it takes notes and uses the tools.

### The `voice/` folder

```
voice/
├── IDEAS.md
├── Package.swift            ← Swift package
├── prompts/
│   └── intent/
│       ├── voice.md         ← GPT-Live prompt
│       ├── backend.md       ← backend model prompt
│       ├── tools.json       ← the 5 tools (name, description, parameters)
│       └── notices.md       ← notices pia-voice pushes to the voice
└── Sources/pia-voice/
    ├── main.swift           ← `pia-voice intent <work>`
    ├── Live/                ← GPT-Live WebSocket and its events
    ├── Tools/               ← what happens when the model calls each tool
    ├── Bridge/              ← prints lines for the Lead, watches intent.md and CLAUDE_PID
    ├── Audio/               ← microphone, speaker, VAD (Silero)
    └── Notch/               ← shape, dot, cost, meter, pulse (from the old Pia)
```

Prompts live in their own files, not in code, so they can be read and changed without touching Swift. `intent/` is its own folder because features 2 and 3 will have their own prompts.

### What each prompt says

`voice.md` and `notices.md` are written in Spanish, because the Live prompting guide says to write the voice's prompt in the language it speaks. `backend.md` and `tools.json` are in English.

**`voice.md`, the voice:**
- You are PIA's voice in the intent phase. Speak the user's language; Spanish and Spanglish are fine.
- Short turns. Never interrupt.
- Your job is to help the user say what they want: the intention, why, what done looks like, scope, constraints. Only light questions.
- Don't invent technical questions or answer them yourself: those come from Claude.
- When Claude's questions arrive, wait for a pause and offer them. One at a time, with the suggested answer.
- Never decide for the user.
- If asked to search for something, search.

**`backend.md`, the note taker:**
- Call `send_intent` once the intention is understood, even with fields missing, and again whenever something changes.
- Call `check_questions` when a notice arrives or the user asks.
- In `send_answers`, write what the user said without improving it, and mark whether it was their decision.
- `confirm_intent` only after a clear "yes" to the summary.
- `end_voice` when the user asks to stop the voice.

**`tools.json`:** the 5 tools with exact parameters.

**`notices.md`:** the texts pia-voice sends, for example:
- "Claude's round 1 is ready (6 questions). Wait for a pause, then offer them."
- "Session reopened because Claude's questions arrived. Tell the user."

### Outside `voice/`

- `skills/new/SKILL.md`: what the Lead does with `--voice` and how it reads `PIA-VOICE ...` lines.
- `templates/project/PIA.md`: a short section with that protocol.

### Practical

- **API key:** read from `OPENAI_API_KEY`.
- **Binary:** a plugin can't ship compiled Swift, so it's built once with `swift build`. The skill looks for it inside the plugin and, if missing, says how to build it.
- **Cost number:** the docs don't say backend token usage is reported. If it isn't, `$0.00` starts with voice time only.

## 2. Talk through the decisions (later)

While reviewing the decision map (mode `in-the-loop`), talk to it instead of only reading.

**What the human thinks:**
- Gemma is the brain and **loads the decisions** (plus research and plan as needed). When GPT-Live delegates a question, it feels like a web search, but Gemma already has the answer in context and hands it back right away. That's how the model is meant to work.
- **Changes are composed, not fired one by one.** You talk, you change your mind, you decide several things; nothing is sent to the Lead until you say "send it". Then one tool call with the whole batch, and the Lead applies each change with `/pia:change`.
- Keep in mind: Gemma 4 holds 131k tokens. A big research doc may not fit whole; it may need to load only the sections it needs.
- To revisit after feature 1: Responses delegation (tools, simpler) versus client delegation with Gemma.

## 3. Voice that stays with you while agents work (later)

Keep talking while PIA implements, like watching a long tool call with a narrator.

**What the human thinks:**
- The bridge **watches the logs** and speaks when something important happens ("the plan was approved", "implementation finished").
- "How's it going?" is answered by **reading the files directly** (`## Now` in `log.md` and the agent logs), not by asking Claude Code, which would be slow. Claude Code is only for actions that write.
- Cost matters most here, because it's the one that stays open: see the cost note above.
