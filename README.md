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

1. Open `apps/macos/VoiceOps.xcodeproj` in Xcode.
2. Build and run.

If you modify the Xcode project definition, regenerate with:

```
cd apps/macos
xcodegen generate --spec project.yml
```

Hotkeys:

- Hold `Fn` to stream transcription into the focused app; release to stop.
- Hold `Fn + Space` to record and polish via LLM, then insert on release.
- `Option + Space` remains as a manual toggle (debug).

## Notes

- If Accessibility is not enabled, output is still copied to the clipboard.
- The overlay window becomes key to handle Enter/Esc; injection re-activates the previous app.

## Next steps

- Replace LLM stub with OpenAI or a local model.
- Add streaming partials and end-of-speech detection.
- Add model selection and custom prompts.
