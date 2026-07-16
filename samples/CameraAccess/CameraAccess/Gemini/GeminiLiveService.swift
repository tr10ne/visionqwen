import Foundation
import UIKit

enum GeminiConnectionState: Equatable {
    case disconnected
    case connecting
    case settingUp
    case ready
    case error(String)
}

@MainActor
class GeminiLiveService: ObservableObject {
    @Published var connectionState: GeminiConnectionState = .disconnected
    @Published var isModelSpeaking: Bool = false

    var onAudioReceived: ((Data) -> Void)?
    var onTurnComplete: (() -> Void)?
    var onInterrupted: (() -> Void)?
    var onDisconnected: ((String?) -> Void)?
    var onInputTranscription: ((String) -> Void)?
    var onOutputTranscription: ((String) -> Void)?
    // var onToolCall: ((GeminiToolCall) -> Void)?
    // var onToolCallCancellation: ((GeminiToolCallCancellation) -> Void)?
    var onToolCall: ((GeminiFunctionCall) -> Void)?
    
    private var latestPendingFrame: Data?
    private var lastImageSentAt: Date = .distantPast
    private var hasActiveResponse = false
    private var responseCreatePending = false
    
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    private var isIntentionalDisconnect = false

    private var lastUserSpeechEnd: Date?
    private var responseLatencyLogged = false
    private var hasSentAudioOnce = false
    private var pendingFunctionCalls: [String: (name: String, arguments: String)] = [:]

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var connectContinuation: CheckedContinuation<Bool, Never>?
    private let delegate = WebSocketDelegate()
    private var urlSession: URLSession!
    private let sendQueue = DispatchQueue(label: "gemini.send", qos: .userInitiated)

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    func connect() async -> Bool {
        isIntentionalDisconnect = false
        guard let url = GeminiConfig.websocketURL() else {
            connectionState = .error("No API key configured")
            return false
        }

        connectionState = .connecting

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.connectContinuation = continuation

            self.delegate.onOpen = { [weak self] protocol_ in
                guard let self else { return }
                Task { @MainActor in
                    self.connectionState = .settingUp
                    self.sendSetupMessage()
                    self.startReceiving()
                }
            }

            self.delegate.onClose = { [weak self] code, reason in
                guard let self else { return }
                let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "no reason"
                Task { @MainActor in
                    self.resolveConnect(success: false)
                    self.connectionState = .disconnected
                    self.isModelSpeaking = false
                    self.pendingFunctionCalls.removeAll()
                    self.onDisconnected?("Connection closed (code \(code.rawValue): \(reasonStr))")
                    self.scheduleReconnect()
                }
            }

            self.delegate.onError = { [weak self] error in
                guard let self else { return }
                let msg = error?.localizedDescription ?? "Unknown error"
                Task { @MainActor in
                    self.resolveConnect(success: false)
                    self.connectionState = .error(msg)
                    self.isModelSpeaking = false
                    self.pendingFunctionCalls.removeAll()
                    self.onDisconnected?(msg)
                    self.scheduleReconnect()
                }
            }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(GeminiConfig.apiKey)", forHTTPHeaderField: "Authorization")
            self.webSocketTask = self.urlSession.webSocketTask(with: request)
            self.webSocketTask?.resume()

            // Timeout after 15 seconds
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await MainActor.run {
                    self.resolveConnect(success: false)
                    if self.connectionState == .connecting || self.connectionState == .settingUp {
                        self.connectionState = .error("Connection timed out")
                    }
                }
            }
        }

        return result
    }

    func disconnect() {
        isIntentionalDisconnect = true   
        reconnectTask?.cancel()          
        reconnectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        delegate.onOpen = nil
        delegate.onClose = nil
        delegate.onError = nil
        onToolCall = nil
        // onToolCallCancellation = nil
        connectionState = .disconnected
        isModelSpeaking = false
        hasSentAudioOnce = false
        pendingFunctionCalls.removeAll()
        resolveConnect(success: false)
        latestPendingFrame = nil
    }

//    func sendAudio(data: Data) {
//        guard connectionState == .ready else { return }
//        sendQueue.async { [weak self] in
//            guard let self else { return }
//            let base64 = data.base64EncodedString()
//            self.hasSentAudioOnce = true
//            let json: [String: Any] = [
//                "type": "input_audio_buffer.append",
//                "audio": base64
//            ]
//            self.sendJSON(json)
//        }
//    }
    func sendAudio(data: Data) {
        guard connectionState == .ready else { return }

        sendQueue.async { [weak self] in
            guard let self else { return }

            self.sendJSON([
                "type": "input_audio_buffer.append",
                "audio": data.base64EncodedString()
            ])

            self.hasSentAudioOnce = true

            let now = Date()
            if let jpegData = self.latestPendingFrame,
               now.timeIntervalSince(self.lastImageSentAt) >= GeminiConfig.videoFrameInterval {
                self.latestPendingFrame = nil
                self.lastImageSentAt = now

                self.sendJSON([
                    "type": "input_image_buffer.append",
                    "image": jpegData.base64EncodedString()
                ])
            }
        }
    }
    
//    func sendVideoFrame(image: UIImage) {
//        guard connectionState == .ready, hasSentAudioOnce else { return }
//        sendQueue.async { [weak self] in
//            guard let self, let jpegData = image.jpegData(compressionQuality: GeminiConfig.videoJPEGQuality) else { return }
//            guard jpegData.count < 190_000 else { return } // safety margin перед base64
//            let base64 = jpegData.base64EncodedString()
//            let json: [String: Any] = [
//                "type": "input_image_buffer.append",
//                "image": base64
//            ]
//            self.sendJSON(json)
//        }
//    }
    func sendVideoFrame(image: UIImage) {
        guard connectionState == .ready else { return }

        guard let jpegData = image.jpegData(
            compressionQuality: GeminiConfig.videoJPEGQuality
        ), jpegData.count < 190_000 else {
            return
        }

        sendQueue.async { [weak self] in
            self?.latestPendingFrame = jpegData
        }
    }

    // func sendToolResponse(_ response: [String: Any]) {
    //     sendQueue.async { [weak self] in
    //         self?.sendJSON(response)
    //     }
    // }

    func sendToolResponse(callId: String, output: String) {
        sendQueue.async { [weak self] in
            guard let self else { return }

            self.sendJSON([
                "event_id": "event_\(UUID().uuidString)",
                "type": "conversation.item.create",
                "item": [
                    "type": "function_call_output",
                    "call_id": callId,
                    "output": output
                ]
            ])

            if !self.hasActiveResponse {
                self.sendJSON([
                    "event_id": "event_\(UUID().uuidString)",
                    "type": "response.create"
                ])
            } else {
                NSLog("[Gemini] Active response in progress — queuing tool result")
                self.responseCreatePending = true
            }

            NSLog("[Gemini] Tool response sent for call_id: %@", callId)
        }
    }

    func sendTextMessage(_ text: String) {
        guard connectionState == .ready else { return }
        sendQueue.async { [weak self] in
            let item: [String: Any] = [
                "type": "conversation.item.create",
                "item": [
                    "type": "message",
                    "role": "user",
                    "content": [["type": "input_text", "text": text]]
                ]
            ]
            self?.sendJSON(item)
            self?.sendJSON(["type": "response.create"])
        }
    }

    func cancelToolCall(callId: String) {
        guard connectionState == .ready else { return }
        sendQueue.async { [weak self] in
            self?.sendJSON([
                "event_id": "event_\(UUID().uuidString)",
                "type": "conversation.item.create",
                "item": [
                    "type": "function_call_output",
                    "call_id": callId,
                    "output": "{\"error\": \"cancelled_by_user\"}"
                ]
            ])
        }
    }

    // MARK: - Private

    private func scheduleReconnect() {
        guard !isIntentionalDisconnect else { return }
        guard reconnectAttempt < 6 else {
            NSLog("[Gemini] Max reconnect attempts reached, giving up")
            return
        }

        let base = 1.0
        let cap = 20.0
        let delay = min(cap, base * pow(2.0, Double(reconnectAttempt)))
        let jitter = Double.random(in: 0...0.5)
        let totalDelay = delay + jitter

        reconnectAttempt += 1
        NSLog("[Gemini] Reconnecting in %.1fs (attempt %d)", totalDelay, reconnectAttempt)

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(totalDelay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            _ = await self.connect()
        }
    }

    private func resolveConnect(success: Bool) {
        if let cont = connectContinuation {
            connectContinuation = nil
            cont.resume(returning: success)
        }
    }

    private func sendSetupMessage() {
        let setup: [String: Any] = [
            "event_id": "event_\(UUID().uuidString)",
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "voice": GeminiConfig.voice,
                "input_audio_format": "pcm",
                "output_audio_format": "pcm",
                "instructions": GeminiConfig.systemInstruction,
                "turn_detection": [
                    "type": "semantic_vad",
                    "threshold": 0.5,
                    "silence_duration_ms": 800
                ],
                "tools": ToolDeclarations.allDeclarations().map { decl in
                    ["type": "function", "function": decl]
                }
            ]
        ]
        sendJSON(setup)
    }

    private func sendJSON(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        webSocketTask?.send(.string(string)) { _ in }
    }

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let task = self.webSocketTask else { break }
                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        await self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            await self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        let reason = error.localizedDescription
                        await MainActor.run {
                            self.resolveConnect(success: false)
                            self.connectionState = .disconnected
                            self.isModelSpeaking = false
                            self.pendingFunctionCalls.removeAll()
                            self.onDisconnected?(reason)
                            self.scheduleReconnect()
                        }
                    }
                    break
                }
            }
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "session.created", "session.updated":
            connectionState = .ready
            reconnectAttempt = 0 
            resolveConnect(success: true)

        case "input_audio_buffer.speech_started":
            isModelSpeaking = false
            pendingFunctionCalls.removeAll()
            hasActiveResponse = false
            onInterrupted?()

        case "input_audio_buffer.speech_stopped":
            lastUserSpeechEnd = Date()
            responseLatencyLogged = false

        case "response.audio.delta":
            if let base64 = json["delta"] as? String,
               let audioData = Data(base64Encoded: base64) {
                if !isModelSpeaking {
                    isModelSpeaking = true
                    if let speechEnd = lastUserSpeechEnd, !responseLatencyLogged {
                        let latency = Date().timeIntervalSince(speechEnd)
                        NSLog("[Gemini] %.0fms latency (user speech end -> first audio)", latency * 1000)
                        responseLatencyLogged = true
                    }
                }
                onAudioReceived?(audioData)
            }

        case "response.audio_transcript.delta":
            if let delta = json["delta"] as? String {
                NSLog("[Gemini] AI: %@", delta)
                onOutputTranscription?(delta)
            }

        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String, !transcript.isEmpty {
                NSLog("[Gemini] You: %@", transcript)
                onInputTranscription?(transcript)
            }
            
        case "response.created":
            hasActiveResponse = true

        case "response.done":
            isModelSpeaking = false
            pendingFunctionCalls.removeAll()
            responseLatencyLogged = false
            hasActiveResponse = false
            onTurnComplete?()
            
            if responseCreatePending {
                responseCreatePending = false
                sendJSON(["event_id": "event_\(UUID().uuidString)", "type": "response.create"])
            }

        case "response.output_item.added":
            if let item = json["item"] as? [String: Any],
            item["type"] as? String == "function_call",
            let callId = item["call_id"] as? String,
            let name = item["name"] as? String {
                pendingFunctionCalls[callId] = (name: name, arguments: "")
            }

        case "response.function_call_arguments.delta":
            if let callId = json["call_id"] as? String, let delta = json["delta"] as? String {
                pendingFunctionCalls[callId]?.arguments += delta
            }

        case "response.function_call_arguments.done":
            if let callId = json["call_id"] as? String,
            let argumentsStr = json["arguments"] as? String {
                let name = pendingFunctionCalls[callId]?.name ?? ""
                pendingFunctionCalls.removeValue(forKey: callId)
                let argsDict = (try? JSONSerialization.jsonObject(with: Data(argumentsStr.utf8))) as? [String: Any] ?? [:]
                onToolCall?(GeminiFunctionCall(id: callId, name: name, args: argsDict))
            }

        case "error":
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown server error"
            NSLog("[Gemini] Server error: %@", msg)
            hasActiveResponse = false
            connectionState = .error(msg)

        default:
            break
        }
    }
}

// MARK: - WebSocket Delegate

private class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    var onOpen: ((String?) -> Void)?
    var onClose: ((URLSessionWebSocketTask.CloseCode, Data?) -> Void)?
    var onError: ((Error?) -> Void)?

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        onOpen?(`protocol`)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        onClose?(closeCode, reason)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            onError?(error)
        }
    }
}
