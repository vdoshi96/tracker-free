import Combine
import ServiceManagement

public enum LoginItemOperationalStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case operationFailed

    public var isEnabled: Bool {
        self == .enabled
    }
}

/// Derives UI state from `SMAppService.status`; it never persists a shadow Boolean.
@MainActor
public final class LoginItemService: ObservableObject {
    @Published public private(set) var status: LoginItemOperationalStatus

    private let service: SMAppService

    public init(service: SMAppService = .mainApp) {
        self.service = service
        status = Self.map(service.status)
    }

    public func refresh() {
        status = Self.map(service.status)
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard service.status != .enabled else {
                    refresh()
                    return true
                }
                try service.register()
            } else {
                guard service.status != .notRegistered else {
                    refresh()
                    return true
                }
                try service.unregister()
            }
            refresh()
            return status.isEnabled == enabled
                || (enabled && status == .requiresApproval)
        } catch {
            // RECOMMENDATION: expose only a generic operation result. The
            // platform error can include paths or signing details.
            status = .operationFailed
            return false
        }
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
        refresh()
    }

    private static func map(_ status: SMAppService.Status) -> LoginItemOperationalStatus {
        switch status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .operationFailed
        }
    }
}
