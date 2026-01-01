import os
import tempfile
from fastapi import FastAPI, UploadFile, File
from pydantic import BaseModel
import uvicorn

from mlx_audio.stt.utils import load_model
from mlx_audio.stt.generate import generate_transcription

MODEL_ID = os.getenv("ASR_MODEL_ID", "mlx-community/GLM-ASR-Nano-2512-8bit")

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
        res = generate_transcription(model=_model, audio_path=tmp_path, verbose=False)
        text = (res.text or "").strip()
        return TranscribeResp(text=text)
    finally:
        try:
            os.remove(tmp_path)
        except Exception:
            pass


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8765)
