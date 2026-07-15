# VisionQwen

![VisionQwen](assets/teaserimage.png)

A real-time AI assistant for Meta Ray-Ban smart glasses powered by **Qwen** (or any OpenAI-compatible API). See what you see, hear what you say, and take actions on your behalf — all through voice.

This is a fork of [VisionClaw](https://github.com/sseanliu/VisionClaw) with two key changes: Gemini Live replaced by Qwen VL via OpenAI-compatible API, and OpenClaw replaced by **Hermes** as the agentic tool backend.

![Cover](assets/cover.png)

Built on [Meta Wearables DAT SDK](https://github.com/facebook/meta-wearables-dat-ios) (iOS) / [DAT Android SDK](https://github.com/nichochar/openclaw) (Android) + Qwen VL API + Hermes (optional).

**Supported platforms:** iOS (iPhone) and Android (Pixel, Samsung, etc.)

## What It Does

Put on your glasses, tap the AI button, and talk:

- **"What am I looking at?"** -- Qwen sees through your glasses camera and describes the scene
- **"Add milk to my shopping list"** -- delegates to Hermes, which executes the task via your connected backend
- **"Send a message to John saying I'll be late"** -- routes through Hermes to your messaging integrations
- **"Search for the best coffee shops nearby"** -- web search via Hermes, results spoken back

The glasses camera streams at ~1fps to Qwen for visual context, while audio flows bidirectionally in real-time.

## How It Works

![How It Works](assets/how.png)

```
Meta Ray-Ban Glasses (or phone camera)
       |
       | video frames + mic audio
       v
iOS / Android App (this project)
       |
       | JPEG frames (~1fps) + PCM audio (16kHz)
       v
Qwen VL API (OpenAI-compatible endpoint)
       |
       |-- Audio response (PCM 24kHz) --> App --> Speaker
       |-- Tool calls (execute) -------> App --> Hermes Gateway
       |                                              |
       |                                              v
       |                                      Agentic actions: web search,
       |                                      messaging, smart home,
       |                                      notes, reminders, etc.
       |                                              |
       |<---- Tool response (text) <----- App <-------+
       |
       v
  Qwen speaks the result
```

**Key pieces:**
- **Qwen VL API** -- vision-language model via OpenAI-compatible endpoint (DashScope, Ollama, or any compatible backend)
- **Hermes** (optional) -- agentic gateway that gives Qwen the ability to take real-world actions; exposes a standard `/v1/chat/completions` + `/health` API with Bearer token auth
- **Phone mode** -- test the full pipeline using your phone camera instead of glasses
- **WebRTC streaming** -- share your glasses POV live to a browser viewer

---

## Quick Start (iOS)

### 1. Clone and open

```bash
git clone https://github.com/tr10ne/visionqwen.git
cd visionqwen/samples/CameraAccess
open CameraAccess.xcodeproj
```

### 2. Add your secrets

Copy the example file and fill in your values:

```bash
cp CameraAccess/Secrets.swift.example CameraAccess/Secrets.swift
```

Edit `Secrets.swift` with your Qwen API key and endpoint (required) and optional Hermes/WebRTC config:

```swift
static let geminiAPIKey = "YOUR_QWEN_API_KEY"
static let geminiBaseURL = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
// or "http://localhost:11434/v1" for local Ollama
static let geminiModel = "qwen-vl-max"
```

> **Note:** Field names in `Secrets.swift` are unchanged from the original codebase. Set `geminiAPIKey` to your Qwen API key and `geminiBaseURL` to your OpenAI-compatible endpoint.

Get a free API key at [DashScope](https://dashscope.aliyun.com/) or run locally via [Ollama](https://ollama.com/).

### 3. Build and run

Select your iPhone as the target device and hit Run (Cmd+R).

### 4. Try it out

**Without glasses (iPhone mode):**
1. Tap **"Start on iPhone"** -- uses your iPhone's back camera
2. Tap the **AI button** to start a Qwen session
3. Talk to the AI -- it can see through your iPhone camera

**With Meta Ray-Ban glasses:**

First, enable Developer Mode in the Meta AI app:

1. Open the **Meta AI** app on your iPhone
2. Go to **Settings** (gear icon, bottom left)
3. Tap **App Info**
4. Tap the **App version** number **5 times** -- this unlocks Developer Mode
5. Go back to Settings -- you'll now see a **Developer Mode** toggle. Turn it on.

![How to enable Developer Mode](assets/dev_mode.png)

Then in VisionQwen:
1. Tap **"Start Streaming"** in the app
2. Tap the **AI button** for voice + vision conversation

---

## Quick Start (Android)

### 1. Clone and open

```bash
git clone https://github.com/tr10ne/visionqwen.git
```

Open `samples/CameraAccessAndroid/` in Android Studio.

### 2. Configure GitHub Packages (DAT SDK)

The Meta DAT Android SDK is distributed via GitHub Packages. You need a GitHub Personal Access Token with `read:packages` scope.

1. Go to [GitHub > Settings > Developer Settings > Personal Access Tokens](https://github.com/settings/tokens) and create a **classic** token with `read:packages` scope
2. In `samples/CameraAccessAndroid/local.properties`, add:

```properties
github_token=YOUR_GITHUB_TOKEN
```

> **Tip:** If you have the `gh` CLI installed, you can run `gh auth token` to get a valid token. Make sure it has `read:packages` scope -- if not, run `gh auth refresh -s read:packages`.
>
> **Note:** GitHub Packages requires authentication even for public repositories. The 401 error means your token is missing or invalid.

### 3. Add your secrets

```bash
cd samples/CameraAccessAndroid/app/src/main/java/com/meta/wearable/dat/externalsampleapps/cameraaccess/
cp Secrets.kt.example Secrets.kt
```

Edit `Secrets.kt` with your Qwen API key and endpoint:

```kotlin
const val geminiApiKey = "YOUR_QWEN_API_KEY"
const val geminiBaseUrl = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
const val geminiModel = "qwen-vl-max"
```

> **Note:** Field names in `Secrets.kt` are unchanged from the original codebase.

### 4. Build and run

1. Let Gradle sync in Android Studio (it will download the DAT SDK from GitHub Packages)
2. Select your Android phone as the target device
3. Click Run (Shift+F10)

> **Wireless debugging:** You can also install via ADB wirelessly. Enable **Wireless debugging** in your phone's Developer Options, then pair with `adb pair <ip>:<port>`.

### 5. Try it out

**Without glasses (Phone mode):**
1. Tap **"Start on Phone"** -- uses your phone's back camera
2. Tap the **AI button** (sparkle icon) to start a Qwen session
3. Talk to the AI -- it can see through your phone camera

**With Meta Ray-Ban glasses:**

Enable Developer Mode in the Meta AI app (same steps as iOS above), then:
1. Tap **"Start Streaming"** in the app
2. Tap the **AI button** for voice + vision conversation

---

## Setup: Hermes (Optional)

Hermes gives Qwen the ability to take real-world actions. Without it, Qwen operates in voice + vision only mode.

The app communicates with Hermes via a standard OpenAI-compatible `/v1/chat/completions` endpoint with Bearer token auth. Hermes must also expose a `/health` endpoint for connection checks.

### Configure the app

**iOS** -- In `Secrets.swift`:
```swift
static let openClawHost = "http://your-hermes-host"
static let openClawPort = 18789
static let openClawGatewayToken = "your-bearer-token-here"
```

**Android** -- In `Secrets.kt`:
```kotlin
const val openClawHost = "http://your-hermes-host"
const val openClawPort = 18789
const val openClawGatewayToken = "your-bearer-token-here"
```

> **Note:** The field names `openClawHost`, `openClawPort`, and `openClawGatewayToken` are unchanged from the original codebase but now point to your Hermes instance.

> Both iOS and Android also have an in-app Settings screen where you can change these values at runtime without editing source code.

### Hermes API contract

The app expects your Hermes gateway to implement:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | `GET` | Connection check -- must return 2xx-4xx |
| `/v1/chat/completions` | `POST` | Chat with `model: "hermes"`, standard OpenAI messages format |

Auth: `Authorization: Bearer <token>` on all requests. No OpenClaw-specific headers (`x-openclaw-*`) are used.

### Verify connection

```bash
curl -H "Authorization: Bearer your-token" http://your-hermes-host:18789/health
```

---

## Architecture

### Key Files (iOS)

All source code is in `samples/CameraAccess/CameraAccess/`:

| File | Purpose |
|------|---------|
| `Gemini/GeminiConfig.swift` | API keys, model config, system prompt |
| `Gemini/GeminiLiveService.swift` | WebSocket client for Qwen VL API (OpenAI-compatible) |
| `Gemini/AudioManager.swift` | Mic capture (PCM 16kHz) + audio playback (PCM 24kHz) |
| `Gemini/GeminiSessionViewModel.swift` | Session lifecycle, tool call wiring, transcript state |
| `OpenClaw/ToolCallModels.swift` | Tool declarations, data types |
| `OpenClaw/OpenClawBridge.swift` | HTTP client for Hermes gateway (`/health` ping + `/v1/chat/completions`) |
| `OpenClaw/ToolCallRouter.swift` | Routes tool calls to Hermes |
| `iPhone/IPhoneCameraManager.swift` | AVCaptureSession wrapper for iPhone camera mode |
| `WebRTC/WebRTCClient.swift` | WebRTC peer connection + SDP negotiation |
| `WebRTC/SignalingClient.swift` | WebSocket signaling for WebRTC rooms |

### Key Files (Android)

All source code is in `samples/CameraAccessAndroid/app/src/main/java/.../cameraaccess/`:

| File | Purpose |
|------|---------|
| `gemini/GeminiConfig.kt` | API keys, model config, system prompt |
| `gemini/GeminiLiveService.kt` | OkHttp WebSocket client for Qwen VL API (OpenAI-compatible) |
| `gemini/AudioManager.kt` | AudioRecord (16kHz) + AudioTrack (24kHz) |
| `gemini/GeminiSessionViewModel.kt` | Session lifecycle, tool call wiring, UI state |
| `openclaw/ToolCallModels.kt` | Tool declarations, data classes |
| `openclaw/OpenClawBridge.kt` | HTTP client for Hermes gateway (`/health` ping + `/v1/chat/completions`) |
| `openclaw/ToolCallRouter.kt` | Routes tool calls to Hermes |
| `phone/PhoneCameraManager.kt` | CameraX wrapper for phone camera mode |
| `webrtc/WebRTCClient.kt` | WebRTC peer connection (stream-webrtc-android) |
| `webrtc/SignalingClient.kt` | OkHttp WebSocket signaling for WebRTC rooms |
| `settings/SettingsManager.kt` | SharedPreferences with Secrets.kt fallback |

### Audio Pipeline

- **Input**: Phone mic -> AudioManager (PCM Int16, 16kHz mono, 100ms chunks) -> Qwen API
- **Output**: Qwen API -> AudioManager playback queue -> Phone speaker
- **iOS iPhone mode**: Uses `.voiceChat` audio session for echo cancellation + mic gating during AI speech
- **iOS Glasses mode**: Uses `.videoChat` audio session (mic is on glasses, speaker is on phone -- no echo)
- **Android**: Uses `VOICE_COMMUNICATION` audio source for built-in acoustic echo cancellation

### Video Pipeline

- **Glasses**: DAT SDK video stream (24fps) -> throttle to ~1fps -> JPEG (50% quality) -> Qwen VL API
- **Phone**: Camera capture (30fps) -> throttle to ~1fps -> JPEG -> Qwen VL API

### Tool Calling

Both apps declare a single `execute` tool that routes everything through Hermes:

1. User says "Add eggs to my shopping list"
2. Qwen speaks "Sure, adding that now" (verbal acknowledgment before tool call)
3. App sends `toolCall` with `execute(task: "Add eggs to the shopping list")`
4. `ToolCallRouter` sends HTTP POST to Hermes at `/v1/chat/completions` with `model: "hermes"`
5. Hermes executes the task
6. Result returns via `toolResponse`
7. Qwen speaks the confirmation

### WebRTC Live Streaming

Share your glasses POV in real-time to a browser viewer with bidirectional audio and video.

1. Tap the **Live** button in the app
2. The app connects to a signaling server and gets a 6-character room code
3. Share the code -- the viewer opens the server URL in a browser and enters it
4. WebRTC peer connection is established (SDP + ICE via the signaling server)
5. Media flows peer-to-peer: glasses video to browser, browser camera back to iOS PiP

**Key details:**
- **Signaling server**: Node.js + WebSocket, located at `samples/CameraAccess/server/` -- serves the browser viewer and relays SDP/ICE
- **NAT traversal**: Google STUN servers + ExpressTURN relay (fetched from `/api/turn`)
- **Video**: 24 fps, 2.5 Mbps max bitrate
- **Background handling**: 60-second grace period for iOS app backgrounding -- room stays alive for reconnection
- **Constraint**: Cannot run simultaneously with an active AI session (audio device conflict)

For full details, see [`samples/CameraAccess/CameraAccess/WebRTC/README.md`](samples/CameraAccess/CameraAccess/WebRTC/README.md).

---

## Requirements

### iOS
- iOS 17.0+
- Xcode 15.0+
- Qwen API key ([DashScope](https://dashscope.aliyun.com/) or local [Ollama](https://ollama.com/))
- Meta Ray-Ban glasses (optional -- use iPhone mode for testing)
- Hermes instance (optional -- for agentic actions)

### Android
- Android 14+ (API 34+)
- Android Studio Ladybug or newer
- GitHub account with `read:packages` token (for DAT SDK)
- Qwen API key ([DashScope](https://dashscope.aliyun.com/) or local [Ollama](https://ollama.com/))
- Meta Ray-Ban glasses (optional -- use Phone mode for testing)
- Hermes instance (optional -- for agentic actions)

---

## Troubleshooting

### General

**AI doesn't hear me** -- Check that microphone permission is granted. Speak clearly and at normal volume.

**Hermes connection timeout** -- Make sure your phone can reach the Hermes host, the service is running, and the URL/port in Secrets is correct. Verify with:
```bash
curl -H "Authorization: Bearer your-token" http://your-hermes-host:18789/health
```

### iOS-specific

**"API key not configured"** -- Add your Qwen API key in `Secrets.swift` (`geminiAPIKey` field) or in the in-app Settings.

**Echo/feedback in iPhone mode** -- The app mutes the mic while the AI is speaking. If you still hear echo, try turning down the volume.

### Android-specific

**Gradle sync fails with 401 Unauthorized** -- Your GitHub token is missing or doesn't have `read:packages` scope. Check `local.properties`. Generate a new token at [github.com/settings/tokens](https://github.com/settings/tokens).

**API timeout** -- Ensure your `geminiBaseUrl` is reachable from your phone. If using Ollama locally, make sure it's bound to `0.0.0.0` and not just `localhost`.

**Audio not working** -- Ensure `RECORD_AUDIO` permission is granted. On Android 13+, you may need to grant this permission manually in Settings > Apps.

**Phone camera not starting** -- Ensure `CAMERA` permission is granted. CameraX requires both the permission and a valid lifecycle.

For DAT SDK issues, see the [developer documentation](https://wearables.developer.meta.com/docs/develop/) or the [discussions forum](https://github.com/facebook/meta-wearables-dat-ios/discussions).

---

## Credits

VisionQwen is a fork of [VisionClaw](https://github.com/sseanliu/VisionClaw) by Xiaoan Liu, DaeHo Lee, Eric J Gonzalez, Mar Gonzalez-Franco, and Ryo Suzuki.
Original paper: [VisionClaw: Always-On AI Agents through Smart Glasses (arXiv:2604.03486)](https://arxiv.org/abs/2604.03486).

## License

This source code is licensed under the license found in the [LICENSE](LICENSE) file in the root directory of this source tree.
