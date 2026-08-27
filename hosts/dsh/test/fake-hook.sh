#!/usr/bin/env bash
# hosts/dsh/test/fake-hook.sh — responde segun el evento; simula al hook real.
# Escribe una linea por llamada a "$FAKE_HOOK_LOG" (si esta set) para poder
# verificar el ORDEN de las llamadas (cola por sesion, plugin.test.js caso f).
set -u
in="$(cat)"
if [ -n "${FAKE_HOOK_LOG:-}" ]; then
  ev_file="$(printf '%s' "$in" | sed -n 's/.*"hook_event_name":"\([A-Za-z]*\)".*/\1/p')"
  printf '%s\n' "$ev_file" >> "$FAKE_HOOK_LOG"
fi
if [ -n "${FAKE_HOOK_DELAY_MS:-}" ]; then sleep "$(awk "BEGIN{print ${FAKE_HOOK_DELAY_MS}/1000}")"; fi
ev="$(printf '%s' "$in" | sed -n 's/.*"hook_event_name":"\([A-Za-z]*\)".*/\1/p')"
case "$ev" in
  UserPromptSubmit) printf '%s' "$in" | grep -q -- '-saikit' && printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"SUMMONAIKIT HARNESS REQUIRED"}}' ;;
  Stop) printf '%s' "$in" | grep -q 'SUMMONAIKIT HARNESS RECEIPT' || printf '{"decision":"block","reason":"SUMMONAIKIT HARNESS GATE\\n\\nFailed gates:\\n- Missing SUMMONAIKIT HARNESS RECEIPT."}' ;;
  *) : ;;
esac
exit 0
