# Clipswain

**Your Paperclip crew, within reach.**

[简体中文](README.zh-CN.md) · [Contributing](CONTRIBUTING.md) · [Privacy](PRIVACY.md) · [Security](SECURITY.md) · [MIT License](LICENSE)

Clipswain is an independent community iPhone/iPad client for [Paperclip](https://github.com/paperclipai/paperclip). Manage tasks, unblock agents, review approvals, and inspect agent activity using a Board account. It is not affiliated with or endorsed by Paperclip AI or Apple. No server patch is required; write actions change the connected server's data.

This repository provides source builds. It does not provide an official App Store or TestFlight installation channel.

Source is hosted at [icework/clipswain](https://github.com/icework/clipswain). See [Project guide](docs/PROJECT.md) for the layout and app identity.

## Features

- Persistent event inbox with read/unread filters; current questions, confirmations, recovery actions, and approvals.
- Task lists, search, assignee filters, status edits, Markdown discussion, child tasks, dependencies, history, and run output.
- Task documents, authenticated attachment downloads, system preview/share, and deliverable links.
- Agent gallery and organization tree; hire/edit/pause/resume agents, invoke runs, inspect skills, and edit versioned instructions.
- Company delivery/timing statistics and recorded costs.
- Optional AI-assisted drafting; optional local background notifications; Siri / Shortcuts task publication.
- English and Simplified Chinese UI with an in-app language picker.

## Build

Requires macOS, Xcode 26 or newer with an iOS Simulator installed, XcodeGen 2.46.0, and Python 3. The deployment target is iOS 17; newer UI APIs require the iOS 26 SDK to compile. Local verification used Xcode 27.0 / Swift 6.4. CI is configured for GitHub's `macos-26` image with Xcode 26.6; check Actions for its actual result.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Clipswain.xcodeproj -scheme Clipswain \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
python3 scripts/check-localizations.py
python3 scripts/check-public-materials.py
swift test --package-path PaperclipKit
python3 scripts/verify-task-result-downloads.py
python3 scripts/verify-network-security.py
```

For App tests, run `xcodebuild -project Clipswain.xcodeproj -scheme Clipswain -showdestinations`, then use an available simulator UDID:

```bash
xcodebuild -project Clipswain.xcodeproj -scheme Clipswain \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO \
  -only-testing:ClipswainAppTests test
```

The unsigned commands above validate compilation and automated tests. Real Board/AI Keychain operations require a signed build with valid application-identifier entitlements; a simulator build without those entitlements may report Keychain error `-34018`.

For a physical device, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` **only if the file does not exist**. Set your own `DEVELOPMENT_TEAM` and unique `APP_IDENTIFIER`. Preserve existing local configuration. Signing files and the generated project are excluded from Git.

Normal tests need no real credentials. Unset `PAPERCLIP_TEST_URL`, `PAPERCLIP_TEST_TOKEN`, and `PAPERCLIP_TEST_MODEL_CATALOGS` for offline runs. Live server tests are opt-in and create/comment/cancel a task in the first company, as well as create a login challenge; only use disposable instances. The localhost scripts use fake credentials.

Deep links use `clipswain://issue/<id>` and `clipswain://approval/<id>`. Siri uses the application name: “Publish a task in Clipswain”.

## Connect and use

Enter your server's final HTTPS address. The connection form starts with HTTPS; the address must include `https://` or `http://`. Plain HTTP requires explicit permission for that server and can expose credentials and content; custom AI HTTP endpoints have a separate permission. API, download, and AI requests reject redirects, so reverse proxies must serve the final endpoint directly.

A `local_trusted` server can connect without credentials. An `authenticated` server requires browser-approved Board sign-in or a Board API Key. Credentials are saved in the device Keychain. Disconnecting attempts remote revocation and ends the local session; a failed revocation is reported and the key may still be valid on the server. If local Keychain removal fails, connection settings are retained and an error is shown so you can retry after unlocking. Saved inbox history and AI credentials are retained. See [Privacy](PRIVACY.md) for deletion and retention details.

AI drafting is optional. Enabling it sends your text and task-assignment context (company and agent details, plus a parent title when applicable) to the chosen provider. Manual creation works without AI. The settings support OpenCode Go, OpenRouter, Anthropic, and OpenAI-compatible endpoints.

After connecting and selecting a company, add the **Publish task** action in Shortcuts, or use the app's Siri phrases. The action runs in the background and returns the created task identifier. Lock-screen Siri depends on device settings, first unlock, network reachability, and system permissions; validate on a physical device.

## Server compatibility and limits

On 2026-10-23, the required routes were checked in official upstream commit `0fb152ee9493075354fbe9b813c7f2f256f22a52`: CLI auth, attention, interactions, recovery, skills, instructions-bundle, documents, attachments, and work-products. This was a source-level check, not an end-to-end test of that server commit. There is no verified minimum backend release yet. Older servers may lack some interfaces; errors are surfaced instead of being shown as empty results. The [Chinese guide](README.zh-CN.md) includes an interface table.

There is no APNs push service. Foreground updates use polling and iOS decides when background refresh runs. Some runtime configuration and skill management remain in the web UI. Connection-intent interactions require the web UI. Local paths on an agent's machine are not downloadable iPhone attachments. Simulator tests do not establish real lock-screen Siri, background-notification, or iOS 17 device behavior.

Original code is MIT-licensed; upstream palette data retains its [third-party notice](THIRD_PARTY_NOTICES.md). See [Contributing](CONTRIBUTING.md) and the [changelog](CHANGELOG.md).
