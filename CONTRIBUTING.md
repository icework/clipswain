# Contributing

Bug reports, compatibility fixes, tests, and translations are welcome. Start with [README.md](README.md), the [Chinese guide](README.zh-CN.md), or the [project layout](docs/PROJECT.md).

## Development

Use macOS, Xcode 26 or newer with an installed iOS Simulator, XcodeGen 2.46.0, and Python 3. The app runs on iOS 17 or newer, but compiling its newer UI APIs requires the iOS 26 SDK. Local verification has used Xcode 27.0; CI selects Xcode 26.6 on the official `macos-26` image. The runner inventory is maintained by [actions/runner-images](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md).

`project.yml` is the source of truth for the Xcode project. Run `xcodegen generate` after changing project configuration. Do not commit the generated `.xcodeproj`, build outputs, or `Config/Local.xcconfig`. Personal signing settings belong in that ignored file; see its example before configuring a device build.

For a normal change, run the checks relevant to the code you changed:

```bash
python3 scripts/check-localizations.py
python3 scripts/check-public-materials.py
swift test --package-path PaperclipKit
python3 scripts/verify-task-result-downloads.py
python3 scripts/verify-network-security.py
xcodegen generate
xcodebuild -project Clipswain.xcodeproj -scheme Clipswain \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

For App code, also run `ClipswainAppTests` on an installed simulator using the command in the README. The two Python network scripts start disposable localhost fixtures and use fake credentials. Ordinary tests must not contact a real Paperclip server or paid model service. Unset `PAPERCLIP_TEST_URL`, `PAPERCLIP_TEST_TOKEN`, and `PAPERCLIP_TEST_MODEL_CATALOGS` before a routine test run. Live tests are opt-in and may write to the first company; use only a disposable instance.

## Pull requests

Explain the observed problem, resulting behavior, and validation performed. Keep changes focused. Include a regression test for meaningful behavior changes, especially authentication, request routing, persistence, and async state. For UI changes, check both languages and light/dark appearance; include screenshots using synthetic data. Follow [the localization guide](docs/LOCALIZATION.md) when editing user-facing text.

State the backend version or commit used for compatibility work. A mocked response or a route found in upstream source does not establish complete live compatibility. Do not label simulator tests as physical-device Siri, lock-screen, or background-notification validation.

Never include real API keys, company/agent/task records, screenshots containing personal information, local signing settings, private hostnames, or full production logs in issues or patches. Replace fixture values with synthetic examples. Report vulnerabilities through [SECURITY.md](SECURITY.md).

Contributions are made under the project's [MIT License](LICENSE). Preserve third-party notices and record the origin and permitted use of any new asset. Do not add dependencies or copyrighted material whose redistribution terms are unknown.
