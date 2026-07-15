# Changelog

All notable changes to VisionQwen will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Streaming token output support
- Multi-turn conversation memory
- Support for additional local models via Ollama

## [1.0.0] - 2026-07-15

### Changed

**Qwen instead of Gemini:**
- `GeminiLiveService` now targets an OpenAI-compatible REST/WebSocket endpoint instead of the Gemini native protocol
- `GeminiConfig`: `geminiAPIKey` / `geminiBaseURL` / `geminiModel` now point to Qwen endpoint
- System prompt updated for Qwen instruction format
- Default model set to `qwen-vl-max`; compatible with any OpenAI-format vision-language model
- To use DashScope: set `geminiBaseURL` to `https://dashscope-intl.aliyuncs.com/compatible-mode/v1`
- To use Ollama locally: set `geminiBaseURL` to `http://<host>:11434/v1`

**Hermes instead of OpenClaw:**
- `OpenClawBridge` now targets a **Hermes** gateway instead of the OpenClaw local desktop app
- Ping endpoint changed from `/v1/chat/completions` to `/health` for lightweight connection checks
- Removed OpenClaw-specific headers: `x-openclaw-session-key` and `x-openclaw-message-channel` are no longer sent
- `model` field in chat completions body changed from `"openclaw"` to `"hermes"`
- Auth is standard `Bearer` token only
- Hermes must expose `GET /health` (returns 2xx–4xx) and `POST /v1/chat/completions` with standard OpenAI messages format

### Notes
- All original file names, class names, and field names are preserved from the upstream VisionClaw codebase
- The `OpenClaw/` folder and all class names (`OpenClawBridge`, `ToolCallRouter`, etc.) remain unchanged

---

*For upstream (VisionClaw) changes prior to this fork, see the
[VisionClaw CHANGELOG](https://github.com/sseanliu/VisionClaw/blob/main/CHANGELOG.md).*
