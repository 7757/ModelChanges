# ModelChanges

**English** · [简体中文](README.zh-CN.md)

[![Release](https://img.shields.io/github/v/release/7757/ModelChanges)](https://github.com/7757/ModelChanges/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/7757/ModelChanges/total)](https://github.com/7757/ModelChanges/releases)
[![License](https://img.shields.io/github/license/7757/ModelChanges)](LICENSE)

A native macOS app for browsing, deploying, testing, and connecting local Ollama models.

[Product website](https://7757.github.io/ModelChanges/) · [Latest release](https://github.com/7757/ModelChanges/releases/latest)

![ModelChanges website and connection panel in English](docs/readme/hero-en.png)

## Demo

![ModelChanges model browser and local connection demo](docs/assets/modelchanges-demo.gif)

## Install

```bash
curl -fsSL https://7757.github.io/ModelChanges/install.sh | sh
```

## What It Does

- Browse the live Ollama model catalog from a native macOS app.
- Compare model types, variants, estimated download size, and memory fit.
- Deploy a model with one click, then start, stop, or remove it when needed.
- See loaded models and memory usage from the dock and menu bar.
- Copy OpenAI-compatible endpoint examples for apps, SDKs, and agents.
- Test model capabilities such as text, tool calls, embeddings, and image input when supported by the selected model.

## Local Endpoint

Most OpenAI-compatible tools can point to the local Ollama endpoint:

```bash
export OPENAI_BASE_URL="http://localhost:11434/v1"
export OPENAI_API_KEY="ollama"
export OPENAI_MODEL="qwen2.5:7b"
```

```python
from openai import OpenAI

client = OpenAI(base_url="http://localhost:11434/v1", api_key="ollama")
response = client.chat.completions.create(
    model="qwen2.5:7b",
    messages=[{"role": "user", "content": "Hello!"}],
)
print(response.choices[0].message.content)
```

## Build

Requirements: macOS 14+ and Xcode command-line tools.

```bash
./Scripts/build_app.sh debug run
./Scripts/build_app.sh release
open dist/ModelChanges.app
```

## How It Works

```text
SwiftUI app  ->  Ollama server on localhost:11434  ->  local model
                  /api/tags       list installed models
                  /api/ps         list running models
                  /api/pull       download with streamed progress
                  /api/generate   load and unload with keep_alive
                  /api/delete     remove a model
```

The live model catalog is fetched from `https://ollama.com/library`, cached locally, and refreshed on demand.

## Roadmap

Ongoing work, roughly in priority order:

- **Signed & notarized builds** — ship with a Developer ID so first launch has no Gatekeeper prompt.
- **In-app auto-update** — check GitHub Releases and update in place.
- **Agent presets** — save a base URL + model as a named profile and copy it into common frameworks in one click.
- **Live throughput** — show tokens/sec and time-to-first-token per running model.
- **Quantization picker** — choose the exact tag/quant per model instead of the default.
- **Multi-turn playground** — a small chat window for quick manual testing, not just single prompts.
- **Slimmer runtime** — trim the bundled engine further, with an optional download-on-first-run.
- **Hugging Face GGUF search** — pull community GGUF models directly, not just the Ollama library.
