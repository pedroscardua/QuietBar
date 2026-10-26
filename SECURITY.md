# Security policy

Security fixes target the latest public release and `main`; older releases have no guaranteed support window.

For vulnerabilities, use [GitHub private vulnerability reporting](https://github.com/pedroscardua/my-noise/security/advisories/new). Include version, macOS version, reproduction steps and impact. Do not post credentials, signing material or private presets in public issues. There is currently no guaranteed response SLA.

The app has no network service or telemetry. Imported JSON and links are untrusted input. If a problem is not security-sensitive, use a regular bug report.

Release binaries are ad-hoc signed and not notarized. Published SHA-256 files check integrity against the release download; they are not an independent publisher identity proof.
