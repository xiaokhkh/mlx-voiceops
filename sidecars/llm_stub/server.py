from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn

app = FastAPI(title="LLM Stub Sidecar")


class Req(BaseModel):
    mode: str
    text: str


class Resp(BaseModel):
    output: str


@app.post("/v1/llm/generate", response_model=Resp)
def generate(req: Req):
    if req.mode == "polish":
        out = f"（润色）{req.text}"
    elif req.mode == "action":
        out = f"背景：\n- {req.text}\n\nTODO：\n- （待补）\n"
    else:
        out = req.text
    return Resp(output=out)


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8787)
