# Changelog

All notable changes to VisionQwen will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Streaming token output support
- Multi-turn conversation memory
- Support for local Qwen models via Ollama

## [1.0.0] - 2026-07-15

### Added
- Replaced Gemini Live API with Qwen VL via OpenAI-compatible API endpoints
- Configurable `qwenBaseUrl` to use DashScope, Ollama, or any compatible backend
- Configurable `qwenModel` field in `Secrets.swift` / `Secrets.kt`
- Support for `qwen-vl-max` and other Qwen vision-language models

### Changed
- `GeminiLiveService` refactored into `QwenVLService` with standard REST/WebSocket transport
- `GeminiConfig` renamed to `QwenConfig`
- `GeminiSessionViewModel` renamed to `QwenSessionViewModel`
- System prompt updated for Qwen instruction format
- All references to Gemini API key replaced with Qwen API key configuration

### Removed
- Direct Gemini Live SDK dependency
- Gemini-specific WebSocket framing

---

*For upstream (VisionClaw) changes prior to this fork, see the
[VisionClaw CHANGELOG](https://github.com/sseanliu/VisionClaw/blob/main/CHANGELOG.md).*
