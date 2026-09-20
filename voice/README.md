# PIA Voice

Two things, both optional, both macOS only. PIA works exactly the same without either.

- **Dictation** — ⌥Space, `gpt-transcribe`, the text lands in your clipboard. Never reaches Claude.
- **The talk, out loud** — `/pia:new --voice`. The same conversation as the typed one, spoken.

Both draw the same island in the notch. Red is dictation, white is the talk.

## Setup

Save an OpenAI key in the Keychain (`OPENAI_API_KEY` works too):

```
security add-generic-password -s pia-voice -a openai -w
```

Needs **macOS 26**. The binary is built on this Mac the first time it's needed — a plugin can't ship
compiled Swift — into a shared folder outside the repo (`scripts/voice-bin.sh`).

## Dictation

`pia-voice dictate serve` runs while Claude Code is open, started by a `SessionStart` hook.

- **⌥Space** — record; press again, click the island, or run `/pia:transcribe` to stop. The text is
  transcribed with `gpt-transcribe` ($0.0045/min) and copied to the clipboard.
- **⌥⇧Space** (or `/pia:transcribe follow`) — the take is **added** to the last one, a blank line
  between them, so you can stop to think and still paste one whole thought. ⌥Space starts over.
- The island shows the live waveform and the elapsed time in red, like Voice Memos. A `+` beside the
  clock means this take is being added to the last one.
- **Two clicks** show this month's cost as a quiet white hint. Hidden by default, and reset for every
  new take.

A `UserPromptExpansion` hook handles `/pia:transcribe` with exit 2, so Claude never sees the command.
Change the shortcut with `PIA_TRANSCRIBE_HOTKEY` (e.g. `ctrl+shift+d`, or `off`); the appending one is
always the same combination plus ⇧. Files live in `~/Library/Application Support/PIA Voice/`, and the
cost resets every month (see *Dictation cost* in the top-level README).

**One daemon per Mac**, enforced against the process table rather than the PID file: two of them would
interleave takes into the same recording and hand OpenAI a corrupt file.

## The talk, out loud

`/pia:new --voice`. **Claude is the brain.** It reads the code, asks the scout and decides what to say.
Everything in front of it is mouth and ears.

```
you ──speak──▶ GPT-Live ──▶ backend ──tell_claude──▶ stdout ──▶ Claude (the lead)
                   ▲                                                 │
                   └───────── logs/voice-inbox.txt ◀─────────────────┘
```

There is a small model between the voice and Claude, and there has to be: **a GPT-Live session cannot
carry its own tools.** They only exist under `delegation.responses.tools`, and a session that declares
`tools`/`tool_choice` on itself is rejected with `Unknown parameter: 'session.tool_choice'` and never
opens at all. What changed is its job: it used to fill in six-field notes and poll for the next round
of questions; now it passes sentences along and nothing else.

Two directions, no protocol:

- **Out:** `tell_claude(text)` — free text, the person's own words — and `pia-voice` prints
  `PIA-VOICE SAID {…}`, which reaches the lead as an event.
- **In:** the lead runs `scripts/voice-say.sh <work> "…"`, which appends to `logs/voice-inbox.txt`.
  A poller picks it up and pushes it into the live session, and the voice says it in its own words.

The inbound half has to be a file rather than a tool call, because Claude answers on its own clock —
it might be thirty seconds deep in the code. A tool call is synchronous: the session would freeze and
the voice would go silent waiting for it. (That is exactly what the old `check_questions` poll was,
and why it sounded like a form.) The script exists so the lead never touches the file directly: a
live session **rejects any single append over 500 tokens** and drops the whole thing, so the script
splits long answers at sentence ends.

### Who writes for whom

Claude writes **like Claude**, in its normal voice. It does not pre-format for speech, and it should
not: the voice is the one that knows whether you just interrupted, whether you already heard half the
list, whether you asked about one thing only. Claude can't see any of that.

So the voice owns *how* it is said — and one thing it may not touch: **names, numbers, prices and
versions are spoken exactly as given.** Everything else is its to phrase.

Two rules on Claude's side, and both exist only because it is spoken:

- **One idea per message.** A list becomes a headline plus an offer, not five messages in a row.
- **The terminal complements, it never echoes.** You hear "Syncfusion is free under a million a year";
  the terminal shows the name spelled out and the link.

### The island is the switch

A live session bills **by the second, silence included**. So:

- It **closes itself** after about 20 seconds of quiet.
- **Speaking never reopens it.** A cough near the microphone can't start billing.
- **One click**, or ⌥V, wakes it or puts it back to sleep. **Two clicks** show what this talk has cost.
- The dot is the state: white while a session is open, **blue** while something could not be delivered
  and is being held, a quiet breathing ring when it is asleep.
- The waveform is **your microphone only**, and the island's breathing comes from the audio GPT-Live
  sent, before it reaches the speakers — so how loud you have your Mac changes nothing.

While asleep the microphone stays open **locally** — that is what makes waking instant and lets the
chime play — but nothing leaves this Mac and nothing is billed.

### When Claude has something and the island is asleep

The session reopens and the voice says it. There is no quiet mode: it was built, it never chimed, and
a setting nobody uses is a setting that hides bugs.

### Starting

`pia-voice` opens a session and says hello **immediately**, before Claude has read anything, and tells
you it is catching up. A person would; leaving you in front of a silent island for a minute is what it
did before.

### Ending

`PIA-VOICE ENDED` means **the voice stopped, not that you left.** Unless you clearly said you're going
away, the work stays `in-the-loop` and the lead carries on in the terminal, writing normally.
Out-of-the-loop is never inferred — see `PIA.md` → *When the human isn't there*.

Three ways out: say it ("ya no quiero hablar"), tell Claude to stop it, or `pkill -f "pia-voice intent"`.
`pia-voice` also watches `CLAUDE_PID` and exits when Claude Code closes. The conversation is kept in
`logs/voice.md`; `talk.md` is written by the lead, the same as in the typed talk.

## Commands

```
pia-voice intent <work dir> [--hotkey <keys>|off] [--voice <name>] [--backend-model <m>] [--idle <s>]
pia-voice dictate toggle [--append] | ensure | stop
pia-voice dictate serve [--record [--append]] [--hotkey <keys>|off] [--stay]
pia-voice transcribe <audio file>
pia-voice notch demo [--voice] [--append] [--capsule|--notch] [--cycle] [--quiet]
```

`notch demo` is the island with a fake voice: no microphone, no API key, nothing billed. It is how the
shape, the motion and the screen-following get judged without spending anything.

## Layout

```
voice/
├── Package.swift
├── prompts/intent/
│   ├── voice.md        the GPT-Live prompt, in Spanish (the language it speaks)
│   ├── backend.md      the model that carries sentences to Claude
│   ├── tools.json      tell_claude, end_voice
│   └── notices.md      what pia-voice pushes into a live session
└── Sources/
    ├── PiaVoiceCore/   the WebSocket protocol, the bridge, transcription, cost, keychain
    ├── PiaVoiceAudio/  microphone, speaker with echo cancellation, local VAD (Silero)
    ├── PiaVoiceNotch/  the island: shape, waveform, clock, cost, pulse, screens and Spaces
    └── pia-voice/      the executable: the dictation daemon, the talk session, the mockup
```

Prompts live in files, not in code, so they can be changed without touching Swift.

## Facts worth keeping

- **GPT-Live-1** costs **$0.05/min**, billed per second, and **silence is billed**: time when you
  speak, when it speaks, and when both are quiet ([cost guide](https://developers.openai.com/api/docs/guides/voice-latency-cost)).
- Audio and text only. No images in or out.
- Context 128k. Startup instructions up to 16,384 tokens; a new session can open with up to 8,192
  tokens of history (`input`, max 128 messages); each mid-session append is capped at 500 tokens
  ([sessions](https://developers.openai.com/api/docs/guides/live-conversations)).
- The client can push context at any time: `session.thinking.append` (known, not spoken),
  `session.commentary.append` (spoken, paraphrased), `session.instructions.append`.
- The assistant can speak first: push instructions and keep input audio running.
- `session.usage.updated` reports the cumulative session seconds — that is where the clock comes from.
- A function call arrives as `response.output_item.done` (`call_id`, `name`, `arguments`); the client
  answers with `response.item.create` carrying a `function_call_output`, then `response.create`.
- **`gpt-transcribe`** costs $0.0045/min.
- Each mid-session context append is capped at **500 tokens**. Going over doesn't truncate — the whole
  append is rejected and the voice says nothing at all.

## Not built yet

**Talk through the decision map.** While reviewing decisions `in-the-loop`, talk to them instead of
only reading. Changes would be composed rather than fired one at a time: you talk, you change your
mind, and nothing reaches the lead until you say send it — then one batch, applied like `/pia:change`.

**A voice that stays while the agents work.** Watch the logs and speak when something real happens
("the decisions are approved", "implementation finished"). "How's it going?" answered by reading
`## Now` directly rather than asking Claude Code. Cost matters most here, because this is the one that
would stay open.
