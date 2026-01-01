#!/usr/bin/env bash
set -euo pipefail

TMP_WAV="$(mktemp /tmp/voiceops_XXXXXX.wav)"

python3 - <<'PY' "$TMP_WAV"
import sys
import wave

path = sys.argv[1]
rate = 16000
seconds = 1
samples = b"\x00\x00" * rate * seconds

with wave.open(path, "wb") as wf:
    wf.setnchannels(1)
    wf.setsampwidth(2)
    wf.setframerate(rate)
    wf.writeframes(samples)
PY

NO_PROXY=127.0.0.1,localhost curl -s -X POST \
  -F "file=@${TMP_WAV}" \
  http://127.0.0.1:8765/v1/asr/transcribe

echo
rm -f "$TMP_WAV"
