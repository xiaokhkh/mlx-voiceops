# MLX VoiceOps

中文 | English: [README.en.md](README.en.md)

MLX VoiceOps 是一个 macOS 菜单栏 App（SwiftUI），配合本地 ASR sidecar 和离线 LLM。按住 **Fn** 时会在小窗里显示流式预览，松开后插入最终结果。

## 架构

- macOS App：Fn 按住录音、小窗预览、最终 ASR、LLM 翻译、Cmd+V 注入。
- 快速 ASR sidecar：FastAPI + sherpa-onnx，PCM 分片 -> 流式文本。
- 最终 ASR sidecar：FastAPI + mlx-audio，wav -> 最终文本。
- 离线 LLM：Ollama `/api/chat`，把最终文本翻译成英文（失败则回退原文）。
- 可选 LLM stub：FastAPI 示例服务（默认不使用）。

## 目录结构

```
apps/macos/VoiceOps/...
sidecars/asr_mlx/...
sidecars/fast_asr/...
sidecars/llm_stub/...
scripts/dev_run.sh
```

## Sidecar 运行

### 最终 ASR（mlx-audio）

```
cd sidecars/asr_mlx
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

### 快速 ASR（sherpa-onnx）

```
cd sidecars/fast_asr
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

### LLM stub（可选）

```
cd sidecars/llm_stub
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python server.py
```

### 开发环境一键启动

```
./scripts/dev_run.sh
```

## 离线 LLM（Ollama）

```
ollama serve
ollama pull qwen2.5-coder:7b-instruct-q5_1
```

App 会调用 `http://127.0.0.1:11434/api/chat` 将最终文本翻译成英文。

## macOS App

1. 用 Xcode 打开 `apps/macos/VoiceOps.xcodeproj`。
2. Build & Run。

如果修改了 `project.yml`，需要重新生成：

```
cd apps/macos
xcodegen generate --spec project.yml
```

快捷键：

- 按住 `Fn`：小窗显示流式预览；松开后插入英文翻译结果。
- `Option + Space`：手动切换录音（调试用）。

## 备注

- 需要开启辅助功能（Accessibility）权限才能注入文本。
- 小窗不会抢焦点，输入焦点始终在目标应用。
