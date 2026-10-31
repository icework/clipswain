# Security policy

## Reporting a vulnerability

Report vulnerabilities privately through the repository's Security tab ("Report a vulnerability"); please do not open a public issue for them. Do not paste API keys, server credentials, private company records, production logs, or exploit details into public issues. No guaranteed response time is offered.

Include the affected app commit, OS version, backend version, expected and actual behavior, and a minimal reproduction with synthetic data. If credentials may have been exposed, revoke them at the relevant server or provider; deleting a local copy alone does not revoke a credential.

## Scope and boundaries

This is a pre-1.0 community client. Fixes are developed on the current main branch; no older release branch is maintained. It uses the authority of the Board API Key provided by the user. Task publication, edits, approvals, agent controls, and instruction edits can change server state.

- The connection form starts with HTTPS; an explicit `http://` or `https://` scheme is required. Plain HTTP requires explicit permission for the selected server; an AI custom endpoint requires its own explicit permission. HTTP can expose credentials and content to network observers.
- API, attachment, and AI requests reject automatic redirects. Configure the final API origin directly, including its correct HTTPS scheme and path. Do not depend on a proxy redirect to carry authorization.
- Credentials are stored in the device Keychain. Local logout and confirmed server revocation are different outcomes; revocation failures are reported to the user.
- Server content and model output are untrusted. Do not run shell commands or install software from a task document simply because the app displays it.
- Background alerts and lock-screen shortcuts are optional system features. Consider whether task titles and spoken results should be visible or audible on a locked device.

See [PRIVACY.md](PRIVACY.md) for data flows and retention. GitHub Actions uses read-only repository permissions, no production credentials, and local fixture servers for transport tests.
