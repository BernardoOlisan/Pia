# PIA Voice

Dictation, macOS only and optional: ⌥Space, `gpt-transcribe`, and the text lands in your clipboard.
It never reaches Claude, and PIA works exactly the same without it.

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

## Commands

```
pia-voice dictate toggle [--append] | ensure | stop
pia-voice dictate serve [--record [--append]] [--hotkey <keys>|off] [--stay]
pia-voice transcribe <audio file>
pia-voice notch demo [--append] [--capsule|--notch] [--cycle] [--quiet]
```

`notch demo` is the island with a fake voice: no microphone, no API key, nothing billed. It is how the
shape, the motion and the screen-following get judged without spending anything.

## Layout

```
voice/
├── Package.swift
└── Sources/
    ├── PiaVoiceCore/   transcription, the dictation buffer and its monthly ledger, keychain
    ├── PiaVoiceAudio/  the microphone and the recorder
    ├── PiaVoiceNotch/  the island: shape, waveform, clock, cost, screens and Spaces
    └── pia-voice/      the executable: the dictation daemon and the mockup
```

## Facts worth keeping

- **`gpt-transcribe`** costs $0.0045/min.

PIA used to have a second thing here: the talk out loud with GPT-Live (`/pia:new --voice`). It was
removed in October 2026; the typed talk is the only one.
