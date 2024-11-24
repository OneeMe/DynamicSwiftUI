// The Swift Programming Language
// https://docs.swift.org/swift-book
import Combine
import DynamicSwiftUITransferProtocol
import Foundation
import Swifter
import SwiftUI

class ServerState: ObservableObject {
    @Published var data: RenderData?
    private let server: LocalServer
    private var cancellables = Set<AnyCancellable>()
    
    init(id: String, server: LocalServer) {
        self.server = server
        
        server.dataPublisher
            .compactMap { jsonString -> RenderData? in
                guard let data = jsonString.data(using: .utf8),
                      let renderData = try? JSONDecoder().decode(RenderData.self, from: data)
                else {
                    print("Failed to decode JSON: \(jsonString)")
                    return nil
                }
                return renderData
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.data, on: self)
            .store(in: &cancellables)
    }
}

public struct DynamicSwiftUIRunner: View {
    let id: String
    @StateObject private var state: ServerState
    private let server: LocalServer
    
    public init(id: String) {
        self.id = id
        let server = LocalServer()
        _state = StateObject(wrappedValue: ServerState(id: id, server: server))
        self.server = server
    }
    
    public var body: some View {
        Group {
            if let node = state.data?.tree {
                buildView(from: node)
            } else {
                EmptyView()
            }
        }
    }
    
    @ViewBuilder
    private func buildView(from node: Node) -> some View {
        switch node.type {
        case .text:
            AnyView(Text(node.data["text"] ?? ""))
        case .button:
            Button(node.data["title"] ?? "") {
                let interactiveData = InteractiveData(id: node.id, type: .tap)
                Task {
                    await server.send(interactiveData)
                }
            }
        case .container:
            if let children = node.children {
                // TODO: Implement container view
                EmptyView()
            }
        }
    }
}

class LocalServer {
    private let server = HttpServer()
    private let dataSubject = PassthroughSubject<String, Never>()
    private var sessions: Set<WebSocketSession> = []
    
    var dataPublisher: AnyPublisher<String, Never> {
        dataSubject.eraseToAnyPublisher()
    }
    
    init() {
        setupServer()
    }
    
    private func setupServer() {
        server["/ws"] = websocket(
            text: { [weak self] _, text in
                print("Received WebSocket message: \(text)")
                self?.dataSubject.send(text)
            },
            binary: { _, _ in
                print("Received binary data")
            },
            connected: { [weak self] session in
                print("WebSocket client connected")
                self?.sessions.insert(session)
            },
            disconnected: { [weak self] session in
                print("WebSocket client disconnected")
                self?.sessions.remove(session)
            }
        )
        
        do {
            try server.start(8080)
            print("WebSocket server started successfully on ws://localhost:8080/ws")
        } catch {
            print("Server start error: \(error)")
        }
    }
    
    func send(_ data: InteractiveData) async {
        guard let jsonData = try? JSONEncoder().encode(data),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return
        }
        
        sessions.forEach { session in
            session.writeText(jsonString)
        }
    }
    
    deinit {
        server.stop()
    }
}
    
