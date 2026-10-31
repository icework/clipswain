import PaperclipKit
import SafariServices
import SwiftUI

/// First-run screen: point the app at a Paperclip server and get a board credential.
///
/// Three paths, picked from the server's deployment mode:
/// - local trusted servers need no credential;
/// - authenticated servers approve a pending board key in the browser (the CLI's flow);
/// - or the user pastes an existing board API key.
struct ConnectView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    @State private var serverText = AppModel.savedServerURL ?? "https://"
    @State private var allowInsecureHTTP = AppModel.savedServerURL.flatMap(URL.init(string:))
        .map { AppModel.allowsInsecureHTTP(for: $0) } ?? false
    @State private var health: ServerHealth?
    @State private var pastedKey = ""
    @State private var challenge: CLIAuthChallenge?
    @State private var approvalURL: URL?
    @State private var waitingTask: Task<Void, Never>?
    @State private var runner = ActionRunner()
    @FocusState private var editingURL: Bool

    private var serverURL: URL? {
        let trimmed = serverText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              (try? TransportSecurityPolicy.validate(url, allowInsecureHTTP: true)) != nil else { return nil }
        return url
    }

    private var usesHTTP: Bool { serverURL?.scheme?.lowercased() == "http" }
    private var mayConnect: Bool { serverURL != nil && (!usesHTTP || allowInsecureHTTP) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        Image("BrandMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: .orange.opacity(0.35), radius: 18, y: 8)
                        Text(AgentsL10n.text("connect.title", "Connect to Paperclip")).font(.largeTitle.weight(.bold))
                        Text(AgentsL10n.text("connect.subtitle", "Track tasks, reply to agents, and manage your AI team."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("https://paperclip.example.com", text: $serverText)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($editingURL)
                        .submitLabel(.go)
                        .onSubmit { Task { await probe() } }
                        .onChange(of: serverText) {
                            health = nil
                            cancelWaiting()
                            allowInsecureHTTP = serverURL.map { AppModel.allowsInsecureHTTP(for: $0) } ?? false
                        }
                    if usesHTTP {
                        Toggle(AppL10n.text("connection.allow_http", "Allow HTTP for this server"), isOn: $allowInsecureHTTP)
                            .onChange(of: allowInsecureHTTP) { health = nil; cancelWaiting() }
                        Text(AppL10n.text("connection.http_warning", "HTTP sends your key and task data without HTTPS protection. Enable only on a network you trust, such as your own protected LAN or Tailscale connection."))
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Button {
                        Task { await probe() }
                    } label: {
                        HStack {
                            Text(AgentsL10n.text("connect.check_server", "Check server"))
                            Spacer()
                            if runner.isBusy && health == nil { ProgressView() }
                        }
                    }
                    .disabled(!mayConnect || runner.isBusy)
                } header: {
                    Text(AgentsL10n.text("connect.server_address", "Server address"))
                } footer: {
                    Text(AppL10n.text("connection.address_help", "Use your Paperclip HTTPS address. Local HTTP servers (usually port 3100) require enabling HTTP for that address. The simulator can reach your Mac at 127.0.0.1; a phone needs a reachable LAN or Tailscale address."))
                }

                if let health {
                    serverSection(health)
                }

                if let error = app.lastError, health == nil {
                    Section { ErrorBanner(message: error) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .readableWidth(620)
            .scrollContentBackground(.hidden)
            .background {
                ZStack(alignment: .top) {
                    Color(.systemGroupedBackground)
                    LinearGradient(colors: [Color(hex: 0xECCA5C).opacity(0.35), Color(hex: 0xFE3C3F).opacity(0.18), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 420)
                }
                .ignoresSafeArea()
            }
            .scrollDismissesKeyboard(.interactively)
            .sensoryFeedback(.success, trigger: health != nil)
            .errorAlert(runner)
            .sheet(item: $approvalURL) { url in
                SafariView(url: url).ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private func serverSection(_ health: ServerHealth) -> some View {
        Section {
            LabeledContent(AgentsL10n.text("connect.version", "Version"), value: health.version ?? "—")
            LabeledContent(AgentsL10n.text("mode.title", "Mode"), value: health.isLocalTrusted ? AgentsL10n.text("connect.mode.trusted", "Locally trusted (no sign-in)") : AgentsL10n.text("connect.mode.authenticated", "Sign-in required"))
        } header: {
            Text(AgentsL10n.text("connect.ready", "Server ready"))
        }

        if health.isLocalTrusted {
            Section {
                Button {
                    Task { await connect(token: nil) }
                } label: {
                    Label(AgentsL10n.text("connect.direct", "Connect directly"), systemImage: "bolt.horizontal.circle")
                }
                .disabled(runner.isBusy)
            }
        } else {
            Section {
                if let challenge {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProgressView()
                            Text(AgentsL10n.text("connect.approval.waiting", "Waiting for approval in your browser…")).font(.subheadline)
                        }
                        Text(AgentsL10n.text("connect.approval.instructions", "Sign in to Paperclip on the page that opens and approve the request. The app will connect automatically."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button(AgentsL10n.text("connect.approval.reopen", "Reopen approval page")) { open(challenge) }
                    Button(AgentsL10n.text("action.cancel", "Cancel"), role: .destructive) { cancelWaiting() }
                } else {
                    Button {
                        Task { await startBrowserApproval() }
                    } label: {
                        Label(AgentsL10n.text("connect.approval.sign_in", "Sign in and approve in browser"), systemImage: "safari")
                    }
                    .disabled(runner.isBusy)
                }
            } header: {
                Text(AgentsL10n.text("connect.approval.method", "Option 1: Approve in browser"))
            } footer: {
                Text(AgentsL10n.text("connect.approval.help", "As with paperclipai CLI sign-in, the app requests a Board API Key that becomes active after you approve it on the web. The key is stored only in this device’s Keychain."))
            }

            Section {
                SecureField("pcp_board_…", text: $pastedKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(AgentsL10n.text("connect.key.submit", "Connect with this key")) {
                    Task { await connect(token: pastedKey.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
                .disabled(pastedKey.trimmingCharacters(in: .whitespaces).isEmpty || runner.isBusy)
            } header: {
                Text(AgentsL10n.text("connect.key.method", "Option 2: Paste a Board API Key"))
            }
        }
    }

    private func probe() async {
        guard mayConnect, let serverURL else { return }
        let consent = allowInsecureHTTP
        editingURL = false
        await runner.run {
            let result = try await PaperclipClient(serverURL: serverURL, token: nil, allowInsecureHTTP: consent).health()
            guard self.serverURL == serverURL, allowInsecureHTTP == consent else { return }
            health = result
        }
    }

    private func connect(token: String?) async {
        guard mayConnect, let serverURL else { return }
        await runner.run {
            try await app.connect(serverURL: serverURL, token: token, allowInsecureHTTP: allowInsecureHTTP)
        }
    }

    private func startBrowserApproval() async {
        guard mayConnect, let serverURL else { return }
        let client = PaperclipClient(serverURL: serverURL, token: nil, allowInsecureHTTP: allowInsecureHTTP)
        await runner.run {
            let created = try await client.createSignInChallenge(clientName: "Clipswain iOS (\(UIDevice.current.name))")
            guard !Task.isCancelled, let current = self.serverURL,
                  PaperclipClient.normalize(current) == client.serverURL,
                  allowInsecureHTTP == client.allowInsecureHTTP else { return }
            challenge = created
            open(created)
            waitForApproval(created, client: client)
        }
    }

    private func open(_ challenge: CLIAuthChallenge) {
        guard let serverURL else { return }
        let client = PaperclipClient(serverURL: serverURL, token: nil, allowInsecureHTTP: allowInsecureHTTP)
        approvalURL = client.approvalURL(for: challenge)
    }

    private func waitForApproval(_ challenge: CLIAuthChallenge, client: PaperclipClient) {
        waitingTask?.cancel()
        waitingTask = Task {
            var policy = SignInPollPolicy(baseInterval: Double(challenge.suggestedPollIntervalMs ?? 1500) / 1000)
            var delay = policy.baseInterval
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                let state: CLIAuthChallengeState
                do {
                    state = try await client.challengeState(id: challenge.id, token: challenge.token)
                } catch {
                    let status = (error as? PaperclipAPIError)?.status
                    switch policy.afterError(status: status, now: .now, expiresAt: challenge.expiresAt) {
                    case .retry(let after):
                        delay = after
                        continue
                    case .stop(let reason):
                        stopWaiting(reason, lastError: error)
                        return
                    }
                }
                if state.isApproved {
                    guard !Task.isCancelled, let current = serverURL,
                          PaperclipClient.normalize(current) == client.serverURL,
                          allowInsecureHTTP == client.allowInsecureHTTP else { return }
                    approvalURL = nil
                    self.challenge = nil
                    await connect(token: challenge.boardApiToken)
                    return
                }
                if state.isFinal {
                    self.challenge = nil
                    runner.errorMessage = state.status == "expired" ? AgentsL10n.text("connect.approval.expired", "The approval request expired. Please try again.") : AgentsL10n.text("connect.approval.cancelled", "The approval request was cancelled.")
                    return
                }
                if case .stop(let reason) = policy.afterPending(now: .now, expiresAt: challenge.expiresAt) {
                    stopWaiting(reason, lastError: nil)
                    return
                }
                delay = policy.baseInterval
            }
        }
    }

    private func stopWaiting(_ reason: SignInPollPolicy.Reason, lastError: Error?) {
        challenge = nil
        approvalURL = nil
        switch reason {
        case .expired: runner.errorMessage = AgentsL10n.text("connect.approval.expired", "The approval request expired. Please try again.")
        case .notFound: runner.errorMessage = AgentsL10n.text("connect.approval.invalid", "The approval request is no longer valid. Please sign in again.")
        case .tooManyFailures:
            runner.errorMessage = AgentsL10n.text("connect.approval.failed", "Unable to confirm approval: \(lastError?.localizedDescription ?? AgentsL10n.text("connect.server_unresponsive", "The server is not responding")). Check your connection and try again.")
        }
    }

    private func cancelWaiting() {
        waitingTask?.cancel()
        waitingTask = nil
        challenge = nil
        approvalURL = nil
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
