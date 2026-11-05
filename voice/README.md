# PIA Voice

Dictation, macOS only and optional: ⌥Space, `gpt-transcribe`, and the text lands in your clipboard.
With no network it is transcribed on the Mac instead, with Parakeet.
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
- **No network** — the island is **cyan instead of red**, and the take is transcribed on this Mac with
  Parakeet TDT 0.6B v3 (FluidAudio, Neural Engine): a 54 s take in about 0.6 s. OpenAI isn't tried at
  all. It also takes over when OpenAI fails or doesn't answer in time (30 s for a short take, up to
  180 s for a long one); the spinner is cyan then. Weaker than `gpt-transcribe` when Spanish and English
  are mixed — it tends to turn parts into English — but the text still lands in the clipboard. The
  model (~470 MB) downloads by itself, once, the first time dictation runs online.
  To try it while connected: `touch ~/Library/Application\ Support/PIA\ Voice/offline`, dictate, and
  `rm` the file to go back.
- **Two clicks** show this month's cost as a quiet white hint. Hidden by default, and reset for every
  new take.

A `UserPromptExpansion` hook handles `/pia:transcribe` with exit 2, so Claude never sees the command.
Change the shortcut with `PIA_TRANSCRIBE_HOTKEY` (e.g. `ctrl+shift+d`, or `off`); the appending one is
always the same combination plus ⇧. Files live in `~/Library/Application Support/PIA Voice/`, and the
cost resets every month (see *Dictation cost* in the top-level README).

## Vocabulary

`vocabulary.txt` in the same folder holds the words the transcriber should know — projects, people,
tools — one per line, `#` for comments. Every take sends it to `gpt-transcribe` as `keywords[]`; it is
read again each time, so an edit applies to the next take. Without the file, only Claude, Claude Code,
PIA and OpenAI are sent. Keep it to words that get misspelled: a long list, or ordinary words, make the
model write terms that were never said. Past 150 terms the rest are cut. Parakeet doesn't use it.

## Every take is kept

Each take is saved in `takes/` as `2026-11-05-093359.m4a` plus `.txt` with its text (the take alone,
not the appended clipboard). About 360 KB per minute of speech — roughly 40 MB a week of heavy use.
Nothing reads it back; it is there to compare transcribers on your own voice. To free the space:

```
rm -rf ~/Library/Application\ Support/PIA\ Voice/takes
```

A take that neither OpenAI nor Parakeet could transcribe goes to `failed/` instead.

**One daemon per Mac**, enforced against the process table rather than the PID file: two of them would
interleave takes into the same recording and hand OpenAI a corrupt file.

## Commands

```
pia-voice dictate toggle [--append] | ensure | stop
pia-voice dictate serve [--record [--append]] [--hotkey <keys>|off] [--stay]
pia-voice transcribe [--local] <audio file>
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
    ├── PiaVoiceLocal/  Parakeet through FluidAudio, the offline fallback
    └── pia-voice/      the executable: the dictation daemon and the mockup
```

## Facts worth keeping

- **`gpt-transcribe`** costs $0.0045/min.
- **Parakeet** is free and local, but it takes no prompt or keywords. FluidAudio is pinned (`0.18.2`)
  with no traits, so its text-to-speech and diarization aren't built in.

PIA used to have a second thing here: the talk out loud with GPT-Live (`/pia:new --voice`). It was
removed in October 2026; the typed talk is the only one.
