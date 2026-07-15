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
- Replaced Gemini Live API backend with Qwen VL via OpenAI-compatible API endpoint
- `GeminiLiveService` now targets OpenAI-compatible REST/WebSocket instead of Gemini native protocol
- `GeminiConfig` updated: `geminiAPIKey` / `geminiBaseURL` / `geminiModel` now point to Qwen endpoint
- System prompt updated for Qwen instruction format
- Default model set to `qwen-vl-max`; compatible with any OpenAI-format vision model

### Notes
- All original file and class names are preserved from the upstream VisionClaw codebase
- To use DashScope: set `geminiBaseURL` to `https://dashscope-intl.aliyuncs.com/compatible-mode/v1`
- To use Ollama locally: set `geminiBaseURL` to `http://<host>:11434/v1`

---

*For upstream (VisionClaw) changes prior to this fork, see the
[VisionClaw CHANGELOG](https://github.com/sseanliu/VisionClaw/blob/main/CHANGELOG.md).*
