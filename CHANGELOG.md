# Changelog

All notable changes to ModelChanges are documented here.

## 1.0.0 - 2026-07-07

- Initial public release.
- Self-contained: the Ollama runtime is bundled inside the app — nothing extra to install. It runs headless on a private model directory and stops when you quit, leaving the host clean.
- Browse the live Ollama model catalog (fetched from ollama.com, cached, auto-refreshed) with type, sizes, pull count, and last-updated info; search, filter by type, sort by popular/newest.
- One-click deploy: download a model and load it into memory, then start / stop / remove it.
- Fits-your-Mac analysis: each variant is labelled from this machine's actual RAM; models that can't fit are disabled, and not-yet-published models are marked "Unavailable".
- Run several models at once, with a live memory-headroom meter.
- Menu-bar control (status icon + quick start/stop) and launch-at-login.
- Local OpenAI-compatible endpoint with copy-paste config and a built-in test panel (chat, tool calls, embeddings, vision).
- Persistent history of everything deployed, started, stopped, or removed.
- Import models from an existing Ollama install, plus a one-click "erase all models & data".
- English and Simplified Chinese, with a GitHub Pages product site and one-line installer.
