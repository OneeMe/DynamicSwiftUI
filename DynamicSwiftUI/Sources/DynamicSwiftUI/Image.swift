//
// DynamicSwiftUI
// Created by: onee on 2024/11/28
//

import DynamicSwiftUITransferProtocol
import Foundation

@MainActor
public struct Image: View {
    let id: String = UUID().uuidString
    let systemName: String
    var imageScale: ImageScale = .medium
    var foregroundStyle: ForegroundStyle = .primary
    
    public init(systemName: String) {
        self.systemName = systemName
    }
    
    public var body: some View {
        self
    }
    
    public func imageScale(_ scale: ImageScale) -> Image {
        var copy = self
        copy.imageScale = scale
        return copy
    }
    
    public func foregroundStyle(_ style: ForegroundStyle) -> Image {
        var copy = self
        copy.foregroundStyle = style
        return copy
    }
}

public enum ImageScale: String {
    case small
    case medium
    case large
}

public enum ForegroundStyle: String {
    case primary
    case secondary
    case tint
}

extension Image: ViewConvertible {
    func convertToNode() -> Node {
        var data: [String: String] = [
            "systemName": systemName,
            "imageScale": imageScale.rawValue,
            "foregroundStyle": foregroundStyle.rawValue
        ]
        return Node(id: id, type: .image, data: data)
    }
} 