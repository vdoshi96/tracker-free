import Foundation

struct StoredPause: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case timed
        case indefinite
    }

    let kind: Kind
    let expiration: Date?
}

@MainActor
final class AppPreferences {
    private enum Key {
        static let hasLaunched = "hasLaunched"
        static let requestedEnabled = "requestedEnabled"
        static let pause = "pause"
        static let disabledBuiltInRuleIDs = "disabledBuiltInRuleIDs"
        static let enabledBuiltInRuleIDs = "enabledBuiltInRuleIDs"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isTrueFirstLaunch: Bool {
        !defaults.bool(forKey: Key.hasLaunched)
    }

    func markLaunched() {
        defaults.set(true, forKey: Key.hasLaunched)
    }

    var requestedEnabled: Bool {
        get { defaults.bool(forKey: Key.requestedEnabled) }
        set { defaults.set(newValue, forKey: Key.requestedEnabled) }
    }

    var storedPause: StoredPause? {
        get {
            guard let data = defaults.data(forKey: Key.pause) else {
                return nil
            }
            return try? JSONDecoder().decode(StoredPause.self, from: data)
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: Key.pause)
                return
            }
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.pause)
            }
        }
    }

    var disabledBuiltInRuleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.disabledBuiltInRuleIDs) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.disabledBuiltInRuleIDs) }
    }

    var enabledBuiltInRuleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.enabledBuiltInRuleIDs) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.enabledBuiltInRuleIDs) }
    }
}
