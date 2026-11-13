import SwiftUI

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case failed(String)

    var title: String {
        switch self {
        case .disconnected:    return "Disconnected"
        case .connecting:      return "Connecting…"
        case .connected:       return "Connected"
        case .disconnecting:   return "Disconnecting…"
        case .failed:          return "Failed"
        }
    }

    var isActive: Bool {
        if case .connected = self { return true }
        return false
    }
}
