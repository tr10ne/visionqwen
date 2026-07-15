import Foundation

// ИЗМЕНЕНО: WebSocket к OpenClaw отключён — Hermes не использует push-уведомления.
// Класс оставлен как заглушка, чтобы не менять GeminiSessionViewModel.
class OpenClawEventClient {
  var onNotification: ((String) -> Void)?

  func connect() {
    NSLog("[OpenClawWS] EventClient disabled (using Hermes, no push WS needed)")
  }

  func disconnect() {
    NSLog("[OpenClawWS] EventClient disabled, nothing to disconnect")
  }
}