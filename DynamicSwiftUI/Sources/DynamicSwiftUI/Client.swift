//
// DynamicSwiftUI
// Created by: onee on 2024/11/24
//

import DynamicSwiftUITransferProtocol
import Foundation

actor WebSocketClient {
    var isConnected = false
    private var webSocket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var continuations: [CheckedContinuation<Data, Error>] = []
    
    func setup() {
        guard let url = URL(string: "ws://localhost:8080/ws") else { return }
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        receiveMessage()
        
        print("WebSocket client connecting to server...")
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { [weak self] in
                await self?.handleReceive(result)
            }
        }
    }
    
    private func handleReceive(_ result: Result<URLSessionWebSocketTask.Message, Error>) {
        switch result {
        case .success(let message):
            switch message {
            case .string(let text):
                print("Received message: \(text)")
                if let data = text.data(using: .utf8),
                   let transferMessage = try? JSONDecoder().decode(TransferMessage.self, from: data)
                {
                    switch transferMessage {
                    case .interactiveData(let interactiveData):
                        handleInteraction(interactiveData)
                    case .initialArg(let data):
                        receivedLaunchData(data)
                    case .renderData:
                        // 客户端不需要处理 renderData
                        break
                    }
                }
            case .data(let data):
                print("Received data: \(data)")
            @unknown default:
                break
            }
            receiveMessage()
        case .failure(let error):
            print("WebSocket receive error: \(error)")
            Task {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                setup()
            }
        }
    }
    
    private func handleInteraction(_ data: InteractiveData) {
        switch data.type {
        case .tap:
            // 找到对应的按钮并触发动作
            Task { @MainActor in
                if let button = InteractiveComponentRegistry.shared.getComponent(withId: data.id) {
                    if let button = button as? Button {
                        Task { @MainActor in
                            button.handleTap()
                        }
                    }
                }
            }
        }
    }
    
    func send(_ data: RenderData) async {
        if !isConnected {
            setup()
        }
        
        let transferMessage = TransferMessage.renderData(data)
        guard let jsonData = try? JSONEncoder().encode(transferMessage),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return
        }
        
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        do {
            try await webSocket?.send(message)
        } catch {
            print("WebSocket send error: \(error)")
        }
    }
    
    func waitForLaunchData() async throws -> Data {
        if !isConnected {
            setup()
        }
        print("wait for server's launch data")
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }
    
    func receivedLaunchData(_ data: Data) {
        if let continuation = continuations.first {
            continuations.removeFirst()
            continuation.resume(returning: data)
        }
    }
    
    deinit {
        webSocket?.cancel(with: .goingAway, reason: nil)
    }
}

let webSocketClient = WebSocketClient()

@MainActor func processView<V: View>(_ view: V) -> Node {
    print("will process view \(type(of: view))")
    if let convertible = view as? ViewConvertible {
        let node = convertible.convertToNode()
        print("node is \(node)")
        return node
    }
    return processView(view.body)
}
