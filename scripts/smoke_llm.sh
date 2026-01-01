#!/usr/bin/env bash
set -euo pipefail

NO_PROXY=127.0.0.1,localhost curl -s -X POST \
  -H 'Content-Type: application/json' \
  -d '{"mode":"polish","text":"hello world"}' \
  http://127.0.0.1:8787/v1/llm/generate

echo
