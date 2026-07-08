# Changelog

All notable changes to ModelChanges are documented here.

## 1.1.1 - 2026-07-08

- Keep models resident for gateway / agent workloads: the bundled server now sets `OLLAMA_KEEP_ALIVE` (default: never unload), so requests that omit `keep_alive` no longer let the model — and its large prompt KV cache — unload. This removes the slow cold re-prefill on the next call (e.g. ~55s for a 22K-token system prompt). Configurable in Settings → Agent performance.
- Optional context-window override (`OLLAMA_CONTEXT_LENGTH`) to avoid silent prompt truncation as agent context grows.
- Warm-up prompt: paste your agent's real system prompt to pre-heat the prefix cache after a deploy, so the first request skips the long prefill.

## 1.1.0 - 2026-07-07

- Self-contained: the Ollama runtime is now bundled inside the app — no separate install. It runs headless on a private model directory and stops cleanly when you quit.
- Import models from an existing Ollama install with one click.
- Not-yet-published models are clearly marked "Unavailable" and can't be deployed; failed pulls now surface a clear error instead of silently doing nothing.
- Catalog sync retries on transient TLS failures.
- Renamed the reset action to "Erase all models & data" — the bundled engine goes with the app (drag ModelChanges to the Trash to remove it).

## 1.0.0 - 2026-07-07

- Initial public release.
- Browse the live Ollama model catalog from a native macOS app.
- Deploy, start, stop, and remove local models with a simple UI.
- Connect apps to a local OpenAI-compatible endpoint.
- Test model capabilities from the connection panel.
- Includes a GitHub Pages product site and one-line installer.
