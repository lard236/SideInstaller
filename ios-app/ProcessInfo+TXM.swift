import Foundation
import Darwin

enum TXMPresence {
    case present
    case absent
    case unknown

    var isPresent: Bool? {
        switch self {
        case .present: return true
        case .absent: return false
        case .unknown: return nil
        }
    }
}

extension ProcessInfo {
    var txmPresence: TXMPresence {
        let isAtLeastIOS17 = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 17
        return isAtLeastIOS17 ? .present : .absent
    }
}
