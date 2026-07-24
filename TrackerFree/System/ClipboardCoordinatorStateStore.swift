import Foundation

@MainActor
public protocol ClipboardCoordinatorStateStoring: AnyObject {
    var requestedEnabled: Bool { get set }
    var pauseUntil: Date? { get set }
    var pauseIndefinitely: Bool { get set }
    var hasPresentedPermissionExplanation: Bool { get set }
}

/// Persists only scalar control state. Clipboard-derived values never enter UserDefaults.
@MainActor
public final class UserDefaultsClipboardCoordinatorStateStore: ClipboardCoordinatorStateStoring {
    private enum Key {
        static let requestedEnabled = "clipboard.requestedEnabled"
        static let pauseUntil = "clipboard.pauseUntil"
        static let pauseIndefinitely = "clipboard.pauseIndefinitely"
        static let hasPresentedPermissionExplanation =
            "clipboard.hasPresentedPermissionExplanation"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var requestedEnabled: Bool {
        get { defaults.bool(forKey: Key.requestedEnabled) }
        set { defaults.set(newValue, forKey: Key.requestedEnabled) }
    }

    public var pauseUntil: Date? {
        get { defaults.object(forKey: Key.pauseUntil) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.pauseUntil)
            } else {
                defaults.removeObject(forKey: Key.pauseUntil)
            }
        }
    }

    public var pauseIndefinitely: Bool {
        get { defaults.bool(forKey: Key.pauseIndefinitely) }
        set { defaults.set(newValue, forKey: Key.pauseIndefinitely) }
    }

    public var hasPresentedPermissionExplanation: Bool {
        get { defaults.bool(forKey: Key.hasPresentedPermissionExplanation) }
        set { defaults.set(newValue, forKey: Key.hasPresentedPermissionExplanation) }
    }
}

@MainActor
public final class InMemoryClipboardCoordinatorStateStore: ClipboardCoordinatorStateStoring {
    public var requestedEnabled: Bool
    public var pauseUntil: Date?
    public var pauseIndefinitely: Bool
    public var hasPresentedPermissionExplanation: Bool

    public init(
        requestedEnabled: Bool = false,
        pauseUntil: Date? = nil,
        pauseIndefinitely: Bool = false,
        hasPresentedPermissionExplanation: Bool = false
    ) {
        self.requestedEnabled = requestedEnabled
        self.pauseUntil = pauseUntil
        self.pauseIndefinitely = pauseIndefinitely
        self.hasPresentedPermissionExplanation = hasPresentedPermissionExplanation
    }
}
