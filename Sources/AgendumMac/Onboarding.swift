import AgendumAppServices
import AgendumFeature
import AgendumSync
import AppKit
import Foundation
import SwiftUI

/// Identifies the literal `gh auth login` command the banner copies to the
/// clipboard. Plain literal (no `GH_CONFIG_DIR` shell quoting): the banner is
/// pure onboarding guidance for the un-authenticated case, so we want the
/// command users would naturally type in Terminal.
public let ghAuthLoginCommand = "gh auth login"

public enum OnboardingDefaults {
    /// `UserDefaults` key set the first time the welcome sheet is dismissed.
    public static let firstRunCompletedKey = "agendum.firstRunCompleted"

    /// Returns `true` if a default base `config.toml` had to be materialized
    /// during this launch. Caller drives first-run sheet visibility from the
    /// returned value (combined with the `UserDefaults` flag).
    @discardableResult
    public static func materializeBaseConfigIfMissing(
        baseDirectory: URL = NativeDashboardService.defaultBaseDirectory()
    ) -> Bool {
        do {
            let paths = try WorkspaceRuntimePaths.workspace(
                namespace: nil,
                baseDirectory: baseDirectory
            )
            return try WorkspaceConfig.materializeDefaultIfMissing(paths: paths)
        } catch {
            // Don't crash launch on disk-full / perms-revoked. Surface enough
            // detail that the failure is debuggable without dropping to a
            // generic "sync failed" message later. Returning false also
            // suppresses the welcome sheet so the user is not misled into
            // thinking onboarding succeeded.
            // Foundation file-IO errors and `WorkspaceConfigError` embed the
            // failing URL, which contains the macOS username. Mark the
            // formatted description `.private` so unified-logs export keeps
            // home-directory paths out of cleartext while still showing
            // enough on local debugging sessions (which preserve private
            // strings) to diagnose.
            logger.error(
                "OnboardingDefaults.materializeBaseConfigIfMissing failed: \(String(describing: error), privacy: .private)"
            )
            return false
        }
    }
}

/// Banner shown above the dashboard when `gh auth status` reports the user is
/// not authenticated. Auto-dismisses (i.e. is not rendered) the next time the
/// auth check succeeds because visibility is recomputed from
/// `DashboardModel.auth` on every update.
struct GhAuthBanner: View {
    let copyCommand: () -> Void

    @State private var didCopy = false

    /// Single `AttributedString` so SwiftUI can line-break inside one Text
    /// rather than between three concatenated Text views — the latter forces
    /// a break around the monospaced run when the window is narrow or
    /// Larger Text is in effect.
    private var bannerInstruction: AttributedString {
        var instruction = AttributedString("Run ")
        var command = AttributedString(ghAuthLoginCommand)
        command.font = .system(.caption, design: .monospaced)
        instruction.append(command)
        instruction.append(AttributedString(" in Terminal, then return to Agendum."))
        return instruction
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("GitHub CLI is not authenticated.")
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(bannerInstruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button {
                copyCommand()
                didCopy = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    didCopy = false
                }
            } label: {
                Label(didCopy ? "Copied" : "Copy command", systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }
            .controlSize(.small)
            .accessibilityIdentifier("gh-auth-banner-copy")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.orange.opacity(0.3))
                .frame(height: 1)
        }
        .accessibilityIdentifier("gh-auth-banner")
    }
}

/// One-shot welcome sheet shown the first time Agendum launches against a
/// freshly materialized workspace. Persists completion in `UserDefaults` so
/// subsequent launches never see it again, even if the user later deletes
/// `~/.agendum/config.toml`.
struct FirstRunWelcomeSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(.tint)
                Text("Welcome to Agendum")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            Text("Agendum surfaces the GitHub pull requests, reviews, and issues that need your attention.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                // Ordered for an actual first-launch user whose ~/.agendum was
                // empty: there are no GitHub workspaces in the sidebar yet, so
                // the auth step has to come first. Workspaces appear after the
                // first sync against an authenticated gh.
                Label("If you haven't yet, run `\(ghAuthLoginCommand)` in Terminal to authenticate the GitHub CLI.", systemImage: "1.circle.fill")
                Label("Click Sync in the toolbar to fetch your tasks.", systemImage: "2.circle.fill")
                Label("Switch between GitHub accounts using the workspace picker that appears in the sidebar after your first sync.", systemImage: "3.circle.fill")
            }
            .font(.callout)
            HStack {
                Spacer()
                Button("Get Started") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("first-run-welcome-dismiss")
            }
        }
        .padding(24)
        .frame(width: 440)
        .accessibilityIdentifier("first-run-welcome-sheet")
    }
}
