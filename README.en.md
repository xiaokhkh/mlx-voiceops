# MLX VoiceOps

English | 中文: [README.zh.md](README.zh.md)

MLX VoiceOps is a macOS menu bar app (SwiftUI) with local ASR sidecars and an offline LLM. It streams partial speech to a small preview panel while you hold **Fn**, then inserts the final result on release.

## Architecture

- macOS app: global Fn hold, non-interactive preview panel, recording, final ASR, LLM translation, text injection via Cmd+V.
- Fast ASR sidecar: FastAPI + sherpa-onnx, PCM chunks in -> partial text out.
- Final ASR sidecar: FastAPI + mlx-audio, wav in -> final text out.
- Offline LLM: Ollama `/api/chat`, translates final text to English (fallbacks to original on failure).
- Optional LLM stub: FastAPI demo endpoint (not used by default).

## Repo layout

```
apps/macos/VoiceOps/...
sidecars/asr_mlx/...
sidecars/fast_asr/...
sidecars/llm_stub/...
scripts/dev_run.sh
```

## Sidecars

### Final ASR (mlx-audio)

```
cd sidecars/asr_mlx
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

### Fast ASR (sherpa-onnx)

```
cd sidecars/fast_asr
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

### LLM stub (optional)

```
cd sidecars/llm_stub
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

### Run all sidecars (dev)

```
./scripts/dev_run.sh
```

## Offline LLM (Ollama)

```
ollama serve
ollama pull qwen2.5-coder:7b-instruct-q5_1
```

The app calls `http://127.0.0.1:11434/api/chat` and translates the final ASR text to English.

## macOS app

1. Open `apps/macos/VoiceOps.xcodeproj` in Xcode.
2. Build and run.

If you modify the Xcode project definition, regenerate with:

```
cd apps/macos
xcodegen generate --spec project.yml
```

Hotkeys:

- Hold `Fn` to show streaming preview; release to stop and insert the final translated text. The hold key is customizable in Preferences.
- Clipboard history hotkey is customizable (default: `Command + Fn`). Configure it from Preferences.

## Notes

- Accessibility permission is required for injection.
- Input Monitoring permission is required for global shortcuts.
- Use Preferences -> Permissions to review and open the required system settings.
- The preview panel never becomes key, so focus stays in the target app.
