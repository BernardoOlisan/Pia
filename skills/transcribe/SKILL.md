---
name: transcribe
description: Dictate with OpenAI's gpt-transcribe. The notch records until you click it (or press ⌥Space again) and the text lands in your clipboard. "follow" adds the take to the last one instead of replacing it. Handled by a hook before it reaches Claude.
argument-hint: "[follow]"
disable-model-invocation: true
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/transcribe.sh" *)
---

# /pia:transcribe [follow]

The plugin's `UserPromptExpansion` hook handles this command before it reaches you, so normally you never read this.

`follow` (or ⌥⇧Space) records a take that is added to the last one, so the clipboard carries everything said since the last fresh take. Plain `/pia:transcribe` (or ⌥Space) starts over.

If you are reading this, the hook didn't run. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/transcribe.sh" <<< "$ARGUMENTS"` and reply with only 🎙️, or with the one-line message it printed if it isn't 🎙️. Nothing else: this is dictation, not a task.
