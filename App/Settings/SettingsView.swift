import PaperclipKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmingSignOut = false
    @State private var notificationsOn = AttentionNotifier.isEnabled
    private var assistant = AssistantSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        StatsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppL10n.text("stats.title", "Statistics"))
                                Text(AppL10n.text("stats.settings_subtitle", "Delivery trends, durations, run reliability, and costs")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    NavigationLink {
                        AssistantSettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            AssistantIcon(size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppL10n.text("assistant.title", "AI assistant"))
                                Text(assistant.summary ?? AppL10n.text("assistant.not_configured", "Not configured · Create tasks in one sentence"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                Section {
                    Picker(AppL10n.text("settings.language", "Language"), selection: Binding(
                        get: { PaperclipLocalization.shared.languageOverride ?? "" },
                        set: { PaperclipLocalization.shared.languageOverride = $0.isEmpty ? nil : $0 }
                    )) {
                        Text(AppL10n.text("settings.language_system", "Follow system")).tag("")
                        ForEach(AppL10n.availableLanguages, id: \.self) { language in
                            Text(Locale(identifier: language).localizedString(forIdentifier: language) ?? language)
                                .tag(language)
                        }
                    }
                } footer: {
                    Text(AppL10n.text("settings.language_help", "Changes apply immediately. Follow system uses your iOS language preference for Clipswain."))
                }

                Section(AppL10n.text("common.company", "Company")) {
                    ForEach(app.companies) { company in
                        Button {
                            Task { await app.selectCompany(company.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Text(String(company.name.prefix(1)))
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(
                                        LinearGradient(colors: [Color(hex: 0xECCA5C), Color(hex: 0xFE3C3F)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(company.name).foregroundStyle(.primary)
                                    if let description = company.description, !description.isEmpty {
                                        Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                if company.id == app.selectedCompanyId {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }

                Section {
                    Toggle(AppL10n.text("settings.background_notifications", "Background notifications"), isOn: $notificationsOn)
                        .onChange(of: notificationsOn) { _, on in
                            Task {
                                if on {
                                    notificationsOn = await AttentionNotifier.requestAuthorization()
                                } else {
                                    AttentionNotifier.isEnabled = false
                                }
                            }
                        }
                } header: {
                    Text(AppL10n.text("settings.notifications", "Notifications"))
                } footer: {
                    Text(AppL10n.text("settings.notifications_help", "While the app is in the background, iOS periodically checks for new agent questions, blockers, or approvals and sends notifications. iOS controls the frequency, typically every few dozen minutes."))
                }

                Section(AppL10n.text("settings.server", "Server")) {
                    LabeledContent(AppL10n.text("common.address", "Address"), value: app.client?.serverURL.absoluteString ?? "—")
                    LabeledContent(AppL10n.text("common.version", "Version"), value: app.health?.version ?? "—")
                    LabeledContent(AppL10n.text("common.mode", "Mode"), value: app.health?.isLocalTrusted == true ? AppL10n.text("settings.local_trust", "Local trust") : AppL10n.text("settings.signed_in", "Signed in"))
                    if let user = app.identity?.user {
                        LabeledContent(AppL10n.text("settings.account", "Account"), value: user.name ?? user.email ?? app.identity?.userId ?? "—")
                    }
                    if let url = app.client?.serverURL {
                        Link(destination: url) {
                            Label(AppL10n.text("settings.open_web", "Open Paperclip in browser"), systemImage: "safari")
                        }
                    }
                }

                Section {
                    Button(AppL10n.text("common.disconnect", "Disconnect"), role: .destructive) { confirmingSignOut = true }
                        .disabled(app.isSigningOut)
                    if let error = app.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text(app.client?.token != nil ? AppL10n.text("settings.revoke_attempt_help", "Disconnecting removes the saved key from this device and attempts to revoke it on the server. If revocation cannot be confirmed, you will be told to revoke it in the browser.") : AppL10n.text("settings.local_trust_help", "No credentials are stored in local trust mode."))
                }

                Section {
                    LabeledContent(AppL10n.text("settings.app_version", "App version"), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                }
            }
            .readableWidth()
            .navigationTitle(AppL10n.text("common.settings", "Settings"))
            .paperclipDestinations()
            .confirmationDialog(AppL10n.text("settings.disconnect_confirmation", "Disconnect from this server?"), isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button(AppL10n.text("common.disconnect", "Disconnect"), role: .destructive) { Task { await app.signOut() } }
            }
        }
    }
}
