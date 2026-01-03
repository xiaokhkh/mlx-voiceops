import os
import sys
import tempfile
from pathlib import Path

from fastapi import FastAPI, UploadFile, File
from pydantic import BaseModel
import uvicorn
import threading
import numpy as np
import soundfile as sf

MODEL_ID = os.getenv("ASR_MODEL_ID", "mlx-community/GLM-ASR-Nano-2512-8bit")
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")


def _ensure_py39_compat() -> None:
    if sys.version_info >= (3, 10):
        return

    try:
        import site

        candidates = []
        if hasattr(site, "getsitepackages"):
            candidates.extend(site.getsitepackages())
        candidates.append(site.getusersitepackages())

        for base in candidates:
            if not base:
                continue
            dsp_path = Path(base) / "mlx_audio" / "dsp.py"
            if not dsp_path.exists():
                continue
            text = dsp_path.read_text(encoding="utf-8")
            if "from __future__ import annotations" in text:
                return
            parts = text.splitlines()
            if parts and parts[0].startswith('"""'):
                end = 1
                while end < len(parts) and not parts[end].startswith('"""'):
                    end += 1
                end = min(end + 1, len(parts))
                parts.insert(end, "")
                parts.insert(end + 1, "from __future__ import annotations")
            else:
                parts.insert(0, "from __future__ import annotations")
            dsp_path.write_text("\n".join(parts) + "\n", encoding="utf-8")
            return
    except Exception:
        pass


_ensure_py39_compat()

from mlx_audio.stt.utils import load_model

app = FastAPI(title="ASR MLX Sidecar")

print(f"[asr] loading model: {MODEL_ID}")
_model = load_model(MODEL_ID)
print("[asr] model ready")


def _warm_up_model() -> None:
    try:
        sr = 16_000
        samples = np.zeros(sr, dtype="float32")
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as fp:
            path = fp.name
        sf.write(path, samples, sr)
        try:
            _model.generate(path, verbose=False)
        except Exception:
            pass
        try:
            os.remove(path)
        except Exception:
            pass
    except Exception:
        pass


threading.Thread(target=_warm_up_model, daemon=True).start()


class TranscribeResp(BaseModel):
    text: str


def _trim_silence(path: str, top_db: float = 40.0) -> int:
    try:
        audio, sr = sf.read(path, dtype="float32")
    except Exception:
        return -1

    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if audio.size == 0:
        return 0

    frame = 1024
    hop = 256
    if audio.size < frame:
        return int(audio.size)

    rms = []
    for i in range(0, audio.size - frame + 1, hop):
        chunk = audio[i : i + frame]
        rms.append(np.sqrt(np.mean(chunk * chunk)))

    if not rms:
        return 0
    rms = np.array(rms)
    max_rms = float(rms.max())
    if max_rms <= 0:
        return 0

    threshold = max_rms * (10 ** (-top_db / 20))
    idx = np.where(rms > threshold)[0]
    if idx.size == 0:
        return 0

    pad = int(sr * 0.05)
    start = max(0, int(idx[0] * hop - pad))
    end = min(audio.size, int(idx[-1] * hop + frame + pad))
    trimmed = audio[start:end]
    if trimmed.size == 0:
        return 0

    if trimmed.size != audio.size:
        sf.write(path, trimmed, sr)
    return int(trimmed.size)


@app.post("/v1/asr/transcribe", response_model=TranscribeResp)
async def transcribe(file: UploadFile = File(...)):
    suffix = ".wav" if file.filename.endswith(".wav") else ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as fp:
        fp.write(await file.read())
        tmp_path = fp.name

    try:
        trimmed_len = _trim_silence(tmp_path)
        if 0 <= trimmed_len < 400:
            return TranscribeResp(text="")

        try:
            res = _model.generate(tmp_path, verbose=False)
        except ValueError as exc:
            if "Input is too short" in str(exc):
                return TranscribeResp(text="")
            raise
        text = (getattr(res, "text", "") or "").strip()
        if not text and getattr(res, "segments", None):
            try:
                text = " ".join(seg.get("text", "").strip() for seg in res.segments).strip()
            except Exception:
                text = ""
        return TranscribeResp(text=text)
    finally:
        try:
            os.remove(tmp_path)
        except Exception:
            pass


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8765)
