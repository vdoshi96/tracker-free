import AppKit
import Foundation

public enum ClipboardLifecycleEvent: Equatable, Sendable {
    case willSleep
    case didWake
    case sessionDidResignActive
    case sessionDidBecomeActive
    case willTerminate
}

@MainActor
public protocol ClipboardLifecycleDelegate: AnyObject {
    func clipboardLifecycleDidReceive(_ event: ClipboardLifecycleEvent)
}

/// Converts AppKit lifecycle notifications into one serialized main-actor event stream.
@MainActor
public final class ClipboardLifecycle: NSObject {
    public weak var delegate: (any ClipboardLifecycleDelegate)?

    private let workspaceNotificationCenter: NotificationCenter
    private let applicationNotificationCenter: NotificationCenter
    private var isStarted = false

    public init(
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationNotificationCenter: NotificationCenter = .default
    ) {
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.applicationNotificationCenter = applicationNotificationCenter
        super.init()
    }

    public func start() {
        guard !isStarted else {
            return
        }
        isStarted = true

        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(handleSessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(handleSessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        applicationNotificationCenter.addObserver(
            self,
            selector: #selector(handleWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    public func stop() {
        guard isStarted else {
            return
        }
        workspaceNotificationCenter.removeObserver(self)
        applicationNotificationCenter.removeObserver(self)
        isStarted = false
    }

    @objc
    private func handleWillSleep() {
        delegate?.clipboardLifecycleDidReceive(.willSleep)
    }

    @objc
    private func handleDidWake() {
        delegate?.clipboardLifecycleDidReceive(.didWake)
    }

    @objc
    private func handleSessionDidResignActive() {
        delegate?.clipboardLifecycleDidReceive(.sessionDidResignActive)
    }

    @objc
    private func handleSessionDidBecomeActive() {
        delegate?.clipboardLifecycleDidReceive(.sessionDidBecomeActive)
    }

    @objc
    private func handleWillTerminate() {
        delegate?.clipboardLifecycleDidReceive(.willTerminate)
    }
}
