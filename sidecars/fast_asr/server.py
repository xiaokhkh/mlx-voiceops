import base64
import os
import threading
import time
import uuid
from pathlib import Path

import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn

import sherpa_onnx

ROOT_DIR = Path(__file__).resolve().parents[2]
MODEL_DIR = os.getenv("FAST_ASR_MODEL_DIR", str(ROOT_DIR / "models" / "zipformer"))
SAMPLE_RATE = int(os.getenv("FAST_ASR_SAMPLE_RATE", "16000"))
FEATURE_DIM = int(os.getenv("FAST_ASR_FEATURE_DIM", "80"))
NUM_THREADS = int(os.getenv("FAST_ASR_NUM_THREADS", "4"))
MODELING_UNIT = os.getenv("FAST_ASR_MODELING_UNIT", "bpe")
BPE_VOCAB = os.getenv("FAST_ASR_BPE_VOCAB", str(Path(MODEL_DIR) / "bpe.model"))

print(f"[fast_asr] loading model from: {MODEL_DIR}")
recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
    encoder=f"{MODEL_DIR}/encoder.onnx",
    decoder=f"{MODEL_DIR}/decoder.onnx",
    joiner=f"{MODEL_DIR}/joiner.onnx",
    tokens=f"{MODEL_DIR}/tokens.txt",
    num_threads=NUM_THREADS,
    sample_rate=SAMPLE_RATE,
    feature_dim=FEATURE_DIM,
    modeling_unit=MODELING_UNIT,
    bpe_vocab=BPE_VOCAB,
)
print("[fast_asr] model ready")

app = FastAPI(title="Fast ASR Sidecar (sherpa-onnx)")
lock = threading.Lock()
sessions = {}


class StartResp(BaseModel):
    session_id: str


class PushReq(BaseModel):
    session_id: str
    samples_b64: str
    sample_rate: int = SAMPLE_RATE


class PushResp(BaseModel):
    text: str
    latency_ms: int


class EndReq(BaseModel):
    session_id: str


class EndResp(BaseModel):
    text: str


@app.get("/health")
def health():
    return {"status": "ok"}


def _extract_text(result) -> str:
    if isinstance(result, str):
        return result
    return getattr(result, "text", "") or ""


@app.post("/v1/fast_asr/start", response_model=StartResp)
def start_session():
    session_id = uuid.uuid4().hex
    stream = recognizer.create_stream()
    sessions[session_id] = stream
    return StartResp(session_id=session_id)


@app.post("/v1/fast_asr/push", response_model=PushResp)
def push_audio(req: PushReq):
    stream = sessions.get(req.session_id)
    if stream is None:
        raise HTTPException(status_code=404, detail="session not found")

    if not req.samples_b64:
        return PushResp(text="", latency_ms=0)

    try:
        data = base64.b64decode(req.samples_b64)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"invalid base64: {exc}") from exc

    if not data:
        return PushResp(text="", latency_ms=0)

    samples = np.frombuffer(data, dtype=np.float32)
    if samples.size == 0:
        return PushResp(text="", latency_ms=0)

    started = time.time()
    with lock:
        stream.accept_waveform(req.sample_rate, samples)
        while recognizer.is_ready(stream):
            recognizer.decode_stream(stream)
        result = recognizer.get_result(stream)
    latency_ms = int((time.time() - started) * 1000)
    return PushResp(text=_extract_text(result), latency_ms=latency_ms)


@app.post("/v1/fast_asr/end", response_model=EndResp)
def end_session(req: EndReq):
    stream = sessions.pop(req.session_id, None)
    if stream is None:
        raise HTTPException(status_code=404, detail="session not found")

    with lock:
        stream.input_finished()
        while recognizer.is_ready(stream):
            recognizer.decode_stream(stream)
        result = recognizer.get_result(stream)
    return EndResp(text=_extract_text(result))


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8790)
