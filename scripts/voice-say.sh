#!/usr/bin/env bash
# Say something to the human through the voice.
#
#   voice-say.sh <work folder> "what to say"
#
# The Lead writes here instead of touching the inbox file, because a live session refuses any single
# append over 500 tokens and silently drops the whole thing. This splits on sentence ends so that can't
# happen: one long paragraph becomes several appends the voice reads in order.
#
# Write like you write to them in the terminal. The voice decides how to say it — it is the one that
# knows whether they just interrupted you.
set -u

work="${1:-}"
text="${2:-}"
if [ -z "$work" ] || [ -z "$text" ]; then
  echo "usage: voice-say.sh <work folder> \"what to say\"" >&2
  exit 1
fi

inbox="$work/logs/voice-inbox.txt"
if [ ! -f "$inbox" ]; then
  echo "voice-say: no voice is running for $work (no $inbox)" >&2
  exit 1
fi

# ~500 tokens. Counted in characters because that is all we can count here, and it errs small for
# Spanish, where a token is worth fewer characters than in English.
LIMIT=1400

python3 - "$inbox" "$LIMIT" "$text" <<'PY'
import re, sys

inbox, limit, text = sys.argv[1], int(sys.argv[2]), sys.argv[3]
text = " ".join(text.split())

pieces, current = [], ""
for sentence in re.split(r"(?<=[.!?:;])\s+", text):
    candidate = f"{current} {sentence}".strip()
    if len(candidate) > limit and current:
        pieces.append(current)
        current = sentence
    else:
        current = candidate
if current:
    pieces.append(current)

# A single sentence longer than the limit still has to be cut somewhere: words, not characters.
final = []
for piece in pieces:
    while len(piece) > limit:
        cut = piece.rfind(" ", 0, limit)
        cut = cut if cut > 0 else limit
        final.append(piece[:cut])
        piece = piece[cut:].lstrip()
    if piece:
        final.append(piece)

with open(inbox, "a", encoding="utf-8") as f:
    for piece in final:
        f.write(piece + "\n")
print(f"said in {len(final)} part{'' if len(final) == 1 else 's'}")
PY
