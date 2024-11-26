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
                   let interactiveData = try? JSONDecoder().decode(InteractiveData.self, from: data)
                {
                    handleInteraction(interactiveData)
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
        
        guard let jsonData = try? JSONEncoder().encode(data),
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
    
    deinit {
        webSocket?.cancel(with: .goingAway, reason: nil)
    }
}

let webSocketClient = WebSocketClient()

@MainActor func processScene<S: Scene>(_ scene: S) -> Node {
    print("scene type is \(type(of: scene))")
    if let windowGroup = scene as? WindowGroup {
        ViewHierarchyManager.shared.setCurrentView(windowGroup.content)
        return processView(windowGroup.content)
    }
    return Node(id: "", type: .container, data: [:])
}

@MainActor func processView<V: View>(_ view: V) -> Node {
    print("will process view \(type(of: view))")
    if let convertible = view as? ViewConvertible {
        return convertible.convertToNode()
    }
    return processView(view.body)
}
