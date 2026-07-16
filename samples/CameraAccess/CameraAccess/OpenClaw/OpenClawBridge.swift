import Foundation

enum OpenClawConnectionState: Equatable {
  case notConfigured
  case checking
  case connected
  case unreachable(String)
}

@MainActor
class OpenClawBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle
  @Published var connectionState: OpenClawConnectionState = .notConfigured

  private let session: URLSession
  private let pingSession: URLSession
  private var sessionKey: String
  private var conversationHistory: [[String: String]] = []
  private let maxHistoryTurns = 10

  private static let stableSessionKey = "agent:main:glass"
  private var currentTask: URLSessionDataTask?
    
  private var activeTaskCount = 0
  private let maxConcurrentTasks = 1

  init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 120
    self.session = URLSession(configuration: config)

    let pingConfig = URLSessionConfiguration.default
    pingConfig.timeoutIntervalForRequest = 5
    self.pingSession = URLSession(configuration: pingConfig)

    self.sessionKey = OpenClawBridge.stableSessionKey
  }

  func checkConnection() async {
    guard GeminiConfig.isOpenClawConfigured else {
      connectionState = .notConfigured
      return
    }
    connectionState = .checking
    // ИЗМЕНЕНО: endpoint /health вместо /v1/chat/completions для пинга
    guard let url = URL(string: "\(GeminiConfig.openClawHost):\(GeminiConfig.openClawPort)/health") else {
      connectionState = .unreachable("Invalid URL")
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    // ИЗМЕНЕНО: Hermes использует простой Bearer token
    request.setValue("Bearer \(GeminiConfig.openClawGatewayToken)", forHTTPHeaderField: "Authorization")
    // УДАЛЕНО: x-openclaw-message-channel — Hermes этого не понимает
    do {
      let (_, response) = try await pingSession.data(for: request)
      if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
        connectionState = .connected
        NSLog("[OpenClaw] Hermes reachable (HTTP %d)", http.statusCode)
      } else {
        connectionState = .unreachable("Unexpected response")
      }
    } catch {
      connectionState = .unreachable(error.localizedDescription)
      NSLog("[OpenClaw] Hermes unreachable: %@", error.localizedDescription)
    }
  }

  func resetSession() {
    conversationHistory = []
    NSLog("[OpenClaw] Session reset (key retained: %@)", sessionKey)
  }

  func delegateTask(
      task: String,
      toolName: String = "execute"
  ) async -> ToolResult {
      guard activeTaskCount < maxConcurrentTasks else {
          NSLog("[OpenClaw] Rejecting overlapping task, already executing")
          return .failure("busy: already executing a previous request")
      }
      activeTaskCount += 1
      defer { activeTaskCount -= 1 }

      lastToolCallStatus = .executing(toolName)

      guard let url = URL(string: "\(GeminiConfig.openClawHost):\(GeminiConfig.openClawPort)/v1/chat/completions") else {
          lastToolCallStatus = .failed(toolName, "Invalid URL")
          return .failure("Invalid gateway URL")
      }

    conversationHistory.append(["role": "user", "content": task])

    if conversationHistory.count > maxHistoryTurns * 2 {
      conversationHistory = Array(conversationHistory.suffix(maxHistoryTurns * 2))
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    // ИЗМЕНЕНО: только стандартные заголовки, без x-openclaw-*
    request.setValue("Bearer \(GeminiConfig.openClawGatewayToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let body: [String: Any] = [
      // ИЗМЕНЕНО: "openclaw" → "hermes" (или имя модели Hermes на вашем VPS)
      "model": "hermes",
      "messages": conversationHistory,
      "stream": false
    ]

    NSLog("[OpenClaw] Sending %d messages to Hermes", conversationHistory.count)

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      try Task.checkCancellation()
      let (data, response) = try await session.data(for: request)
      try Task.checkCancellation()
      let httpResponse = response as? HTTPURLResponse

      guard let statusCode = httpResponse?.statusCode, (200...299).contains(statusCode) else {
        let code = httpResponse?.statusCode ?? 0
        let bodyStr = String(data: data, encoding: .utf8) ?? "no body"
        NSLog("[OpenClaw] Chat failed: HTTP %d - %@", code, String(bodyStr.prefix(200)))
        lastToolCallStatus = .failed(toolName, "HTTP \(code)")
        if conversationHistory.last?["role"] == "user" {
            conversationHistory.removeLast()
        }
        return .failure("Agent returned HTTP \(code)")
      }

      if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let choices = json["choices"] as? [[String: Any]],
         let first = choices.first,
         let message = first["message"] as? [String: Any],
         let content = message["content"] as? String {
        conversationHistory.append(["role": "assistant", "content": content])
        NSLog("[OpenClaw] Hermes result: %@", String(content.prefix(200)))
        lastToolCallStatus = .completed(toolName)
        return .success(content)
      }

      let raw = String(data: data, encoding: .utf8) ?? "OK"
      conversationHistory.append(["role": "assistant", "content": raw])
      lastToolCallStatus = .completed(toolName)
      return .success(raw)
    } catch is CancellationError {
          // ИЗМЕНЕНО: явная обработка отмены — убираем незакрытый user-turn,
          // чтобы следующий запрос не унаследовал рассинхронизированную историю
          NSLog("[OpenClaw] Task cancelled by user, cleaning up history")
          if conversationHistory.last?["role"] == "user" {
              conversationHistory.removeLast()
          }
          lastToolCallStatus = .failed(toolName, "cancelled")
          return .failure("cancelled")
      } catch {
          NSLog("[OpenClaw] Hermes error: %@", error.localizedDescription)
          // ИЗМЕНЕНО: тоже чистим историю при любой другой ошибке сети
          if conversationHistory.last?["role"] == "user" {
              conversationHistory.removeLast()
          }
          lastToolCallStatus = .failed(toolName, error.localizedDescription)
          return .failure("Agent error: \(error.localizedDescription)")
      }
  }
}
