import ShortlistCore
import SwiftUI

/// Phase 0 screen: shows whether the app is signed, when the signature lapses,
/// and whether its data has survived refreshes and updates.
struct StatusView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = InstallStatus.current()

    var body: some View {
        NavigationStack {
            List {
                Section("Signing") {
                    if let profile = status.profile {
                        LabeledContent("Expires", value: Self.format(profile.expirationDate))
                        LabeledContent("Days left", value: Self.daysLeftText(for: profile))
                        if let created = profile.creationDate {
                            LabeledContent("Last signed", value: Self.format(created))
                        }
                    } else {
                        Text("No provisioning profile found. This is expected in the Simulator.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Install") {
                    LabeledContent("First opened", value: status.firstOpened.map(Self.format) ?? "now")
                    LabeledContent("Times opened", value: String(status.openCount))
                    LabeledContent("Version", value: "\(status.appVersion) (\(status.buildNumber))")
                    LabeledContent("Bundle ID", value: status.bundleIdentifier)
                    LabeledContent("iOS", value: status.systemVersion)
                }
            }
            .navigationTitle("Shortlist")
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                status = InstallStatus.current()
            }
        }
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func daysLeftText(for profile: ProvisioningProfile) -> String {
        profile.isExpired() ? "Expired" : String(profile.daysRemaining())
    }
}
