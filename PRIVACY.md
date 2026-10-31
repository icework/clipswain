# Privacy and local data

This document describes the source in this repository. A fork or a separately distributed binary may behave differently. This project includes no analytics, advertising, or maintainer-operated data collection endpoint. It connects to the Paperclip server and optional AI services that you choose; those services receive data needed for the requested operations and have their own retention policies.

## Data sent from the device

| Destination | Data and purpose |
| --- | --- |
| Your Paperclip server | Board credentials, company and task identifiers, task text, comments, answers, approvals, and agent/instruction edits required by the action you request. Reads also disclose normal request metadata, such as the device's network address, to that server. |
| Browser sign-in page | The login challenge needed to approve the client. The browser and server handle their own login/session data. |
| AI provider you configure | When drafting a task: your input text, current date/time zone, company name, available agents' IDs, names, roles, titles and capabilities, and parent-task title when applicable. Model discovery and connection tests also contact the configured provider. OpenCode Go receives client headers and a per-draft session identifier. |
| Links and sharing destinations you open | The selected link or shared document/attachment. Their handling is governed by the selected browser, app, and service. |

AI is optional. Manual task creation does not require a model-provider key. Siri shortcuts can also publish without AI; when AI is enabled, the same drafting data flow applies. Speech recognition and Siri are Apple system services, subject to the device's settings and Apple's policies. The app does not implement a separate audio recording or transcription service.

The connection form starts with HTTPS. Addresses must include `https://` or `http://`; a missing scheme is rejected. Plain HTTP requires an explicit choice for that server; custom AI HTTP endpoints require a separate choice. HTTP does not encrypt credentials or content. Automatic API, download, and AI redirects are rejected; enter the final endpoint directly.

## Data retained on the device

- Board and AI API keys are stored in the Keychain using device-only access after the first unlock. AI keys are scoped to their provider/account and kept separately from the Board key. Keychain persistence is controlled by iOS; do not assume uninstalling the app revokes or erases all credentials.
- App preferences store the server address, selected company, language, notification preferences, and AI provider/model settings in app-specific UserDefaults. Keys are not stored in UserDefaults.
- Inbox history, read/unread state, filters, and notification deduplication records are stored in the app's Application Support directory, separated by server, account, and company. There is no automatic age-based deletion or cross-device sync implemented by this app. OS backup behavior is separate from app sync.
- Downloaded attachments use temporary files for preview. The app attempts to remove those files after preview and cancellation; crashes can leave temporary files until the OS cleans them up. Copies you export through Share are controlled by their destination.
- Local notifications can contain task text or titles. iOS settings control whether previews appear on the lock screen.

## Disconnecting and deleting data

Disconnecting ends the local Board session and disables background refresh notifications. It attempts to revoke the current Board key on the server; if revocation fails, the app reports that result. Revoke the key in Paperclip when necessary. If removal of the local Board key fails, the app keeps the connection settings and reports the error; unlock the device and retry. Local logout does not delete task data on the server, previously saved inbox history, the remembered server address, or independently configured AI credentials.

Reset the selected AI provider in AI settings to delete its locally saved key; repeat for each configured provider as needed. This does not revoke a provider-side key or delete the provider's logs. Removing the app removes its local app container, including the inbox archive; it does not delete remote server data, exported files, or necessarily Keychain entries. Use each server/provider's own controls for remote deletion and revocation.

## Privacy manifests

The App and PaperclipKit each include `PrivacyInfo.xcprivacy`. Both declare `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` because preferences are read and written only in this app's own domain; PaperclipKit stores its language preference there. Neither component uses these preferences for tracking. This follows [Apple's required-reason API documentation](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

The manifests describe required-reason API use. They are not a declaration that no data leaves the device and do not replace an App Store privacy label. Anyone distributing a binary must review its actual service configuration, dependencies, archive privacy report, and data practices before making a store submission.
