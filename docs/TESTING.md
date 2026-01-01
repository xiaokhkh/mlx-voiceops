# Testing checklist

## Sidecars

- Start ASR and LLM servers without errors.
- Run `scripts/smoke_llm.sh` and verify JSON response.
- Run `scripts/smoke_asr.sh` and verify JSON response (likely empty text for silence).
- POST a short wav to `/v1/asr/transcribe` and verify JSON response.
- POST a sample request to `/v1/llm/generate` and verify JSON response.

## macOS app

- Launch app and confirm menu bar icon appears.
- Press Option+Space to start recording, press again to stop.
- Verify overlay shows state transitions: Recording -> Transcribing -> Generating -> Ready.
- Press Enter in overlay to insert output; if Accessibility is disabled, verify clipboard is set.
- Press Esc to cancel and hide overlay.
