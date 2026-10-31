# Clipswain project guide

Clipswain is an independent native iPhone/iPad client for Paperclip. The name combines a reference to Paperclip with the helmsman image of a coxswain: keeping an AI team on course from your phone. Product name: **Clipswain**; directory and proposed repository slug: **clipswain**.

This directory is a clean source copy. It has no inherited Git history, remote, personal signing configuration, credentials, or production screenshots. Historical research and device-specific verification records remain in the original private project. No public repository, website, or store listing has been created.

## Layout

| Path | Purpose |
| --- | --- |
| `App/` | SwiftUI application, background notifications, Siri actions and local state |
| `AppTests/` | Application regression tests |
| `PaperclipKit/` | Backend models, API and AI clients, localization and package tests |
| `Config/` | Shared settings, Info.plist, privacy manifest and signing example |
| `Resources/` | Existing app icon and asset catalogs; attribution in third-party notices |
| `scripts/` | Localization/privacy checks and local HTTP regression fixtures |
| `.github/` | CI workflow and contribution templates |
| `docs/` | Project and localization documentation |

## App identity

- Generated project: `Clipswain.xcodeproj`; App target/scheme: `Clipswain`; test target: `ClipswainAppTests`.
- Default bundle identifier: `space.icework.clipswain`. Override `APP_IDENTIFIER` and `DEVELOPMENT_TEAM` in an untracked `Config/Local.xcconfig` for your own signing.
- URL scheme: `clipswain://issue/<id>` and `clipswain://approval/<id>`.
- Background refresh identifier: `space.icework.clipswain.refresh`.
- Board and AI Keychain service names have a Clipswain namespace. This app can coexist with the original development app; it does not automatically import that app's credentials or preferences. Connect to your server and configure AI again when installing it as a separate app.
- PaperclipKit keeps its name because it implements the Paperclip server contract. Backend concepts, API fields and upstream attribution retain their proper names.

## Development

Install the tools listed in the README, then use:

```sh
make check          # Localization, public materials and privacy manifests
make test           # Offline package tests
make network-test   # Localhost-only download and redirect fixtures
make build          # Generate the project and compile for iOS Simulator
make test-app SIMULATOR_ID=<available-simulator-udid>
```

The generated project and all build outputs are ignored. The build commands do not copy or configure a personal signing team. No project script pushes code or publishes a release.

## Before a release

1. Verify signed-device connection and credential lifecycle, plus any advertised Siri/background behavior.
2. Review the final files and test results. Recheck name availability before registering a domain or store listing; the initial GitHub name search found no matching repository name on 2026-10-23, which is not a trademark clearance.

See [MIT license](../LICENSE), [third-party notices](../THIRD_PARTY_NOTICES.md), [privacy](../PRIVACY.md) and [localization](LOCALIZATION.md).
