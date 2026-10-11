import Foundation
import ServiceManagement

public enum LoginItemState: Equatable {
    case enabled
    case disabled
    /// Registered, but the user has to allow it in System Settings > General > Login Items.
    case requiresApproval
    case unavailable(String)

    public var isOn: Bool { self == .enabled || self == .requiresApproval }
}

public protocol LoginItemControlling: AnyObject {
    var state: LoginItemState { get }
    func set(_ enabled: Bool) throws
}

/// Launch at login through `SMAppService.mainApp` (macOS 13+): no helper app, no LaunchAgent plist.
public final class SystemLoginItem: LoginItemControlling {
    public init() {}

    public var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        case .notFound: return .unavailable("Move NightMode to your Applications folder to launch it at login.")
        @unknown default: return .disabled
        }
    }

    public func set(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else {
            if SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
        }
    }
}

public final class MockLoginItem: LoginItemControlling {
    public var state: LoginItemState
    public init(_ state: LoginItemState = .enabled) { self.state = state }
    public func set(_ enabled: Bool) throws { state = enabled ? .enabled : .disabled }
}
