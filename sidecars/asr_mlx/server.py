import os
import sys
import tempfile
from pathlib import Path

from fastapi import FastAPI, UploadFile, File
from pydantic import BaseModel
import uvicorn

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


class TranscribeResp(BaseModel):
    text: str


@app.post("/v1/asr/transcribe", response_model=TranscribeResp)
async def transcribe(file: UploadFile = File(...)):
    suffix = ".wav" if file.filename.endswith(".wav") else ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as fp:
        fp.write(await file.read())
        tmp_path = fp.name

    try:
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
