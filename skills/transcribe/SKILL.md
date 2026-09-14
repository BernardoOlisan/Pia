---
name: transcribe
description: Dictate with OpenAI's gpt-transcribe. The notch records until you click it (or press ⌥Space again) and the text lands in your clipboard. Handled by a hook before it reaches Claude.
disable-model-invocation: true
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/transcribe.sh" *)
---

# /pia:transcribe

The plugin's `UserPromptExpansion` hook handles this command before it reaches you, so normally you never read this.

If you are reading it, the hook didn't run. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/transcribe.sh" < /dev/null` and reply with only 🎙️, or with the one-line message it printed if it isn't 🎙️. Nothing else: this is dictation, not a task.
