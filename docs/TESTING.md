# Testing checklist

## Sidecars

- Start ASR and LLM servers without errors.
- Run `scripts/smoke_llm.sh` and verify JSON response.
- Run `scripts/smoke_asr.sh` and verify JSON response (likely empty text for silence).
- POST a short wav to `/v1/asr/transcribe` and verify JSON response.
- POST a sample request to `/v1/llm/generate` and verify JSON response.

## macOS app

- Launch app and confirm menu bar icon appears.
- Focus a text field in another app (Slack/Chrome/VSCode).
- Hold Fn to start streaming; verify text appears incrementally in the focused field.
- Release Fn to stop; verify final text is appended.
- Confirm no overlay or focus change occurs during Fn hold.
- If Accessibility is disabled, verify text is copied to clipboard and no injection occurs.
