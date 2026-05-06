import AgendumMacWorkflow
import AppKit
import Foundation
@preconcurrency import UserNotifications

extension BackendStatusModel {
    static func live() -> BackendStatusModel {
        BackendStatusModel(
            openURL: defaultURLOpener,
            pasteboard: defaultPasteboard,
            notifier: defaultNotifier,
            setBadge: defaultBadgeSetter
        )
    }

    private static var defaultURLOpener: URLOpening {
        { url in NSWorkspace.shared.open(url) }
    }

    private static var defaultPasteboard: Pasteboarding {
        { string in
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([.string], owner: nil)
            pasteboard.setString(string, forType: .string)
        }
    }

    private static var defaultNotifier: Notifying {
        { content in
            // UNUserNotificationCenter.current() raises an Obj-C exception
            // when the host process is not a proper application bundle
            // (e.g. the swift-test xctest runner whose main bundle is
            // `/Applications/Xcode.app/Contents/Developer/usr/bin/`).
            // Skip the post in that case so the default seam is safe to
            // invoke from any process.
            guard Bundle.main.bundleURL.pathExtension == "app" else { return }
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
                return
            }
            let mutable = UNMutableNotificationContent()
            mutable.title = content.title
            mutable.body = content.body
            let request = UNNotificationRequest(
                identifier: content.identifier,
                content: mutable,
                trigger: nil
            )
            do {
                try await center.add(request)
            } catch {
                logger.error("UNUserNotificationCenter add failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static var defaultBadgeSetter: BadgeSetting {
        { count in
            MainActor.assumeIsolated {
                let label: String? = count > 0 ? String(count) : nil
                NSApplication.shared.dockTile.badgeLabel = label
                logger.notice("Dock badge updated: \(label ?? "nil", privacy: .public)")
            }
        }
    }
}
