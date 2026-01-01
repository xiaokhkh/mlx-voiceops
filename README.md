# MLX VoiceOps

A macOS menu bar app (SwiftUI) + local ASR sidecar (Python + mlx-audio) + LLM sidecar (stub) for fast voice-to-text workflows.

## Architecture

- macOS app: global hotkey, overlay status, recording, ASR + LLM calls, output injection via Cmd+V.
- ASR sidecar: FastAPI + mlx-audio, wav in -> text out.
- LLM sidecar: FastAPI stub, replaceable with OpenAI or self-hosted.

## Repo layout

```
apps/macos/VoiceOps/...
sidecars/asr_mlx/...
sidecars/llm_stub/...
scripts/dev_run.sh
```

## Sidecars

### ASR (mlx-audio)

```
cd sidecars/asr_mlx
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

### LLM stub

```
cd sidecars/llm_stub
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

### Smoke tests

```
./scripts/smoke_llm.sh
./scripts/smoke_asr.sh
```

## macOS app

1. In Xcode, create a new macOS App project named `VoiceOps`.
2. Set the app to run as a menu bar accessory (AppDelegate in `AppMain.swift`).
3. Drag the files from `apps/macos/VoiceOps/` into the Xcode project target.
4. Add `NSMicrophoneUsageDescription` to `Info.plist`.
5. Build and run.

Hotkey: `Option + Space` (toggle record).

## Notes

- If Accessibility is not enabled, output is still copied to the clipboard.
- The overlay window becomes key to handle Enter/Esc; injection re-activates the previous app.

## Next steps

- Replace LLM stub with OpenAI or a local model.
- Add streaming partials and end-of-speech detection.
- Add model selection and custom prompts.
