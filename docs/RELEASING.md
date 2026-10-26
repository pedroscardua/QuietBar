# Releasing

The project uses semantic versions. The maintainer reviews release content and dependencies; bots do not merge or publish final releases automatically.

1. Update `CFBundleShortVersionString` and increment `CFBundleVersion` in `Info.plist`.
2. Update `CHANGELOG.md` and `docs/RELEASE_NOTES.md`.
3. Run the build, repository checks and silent tests. Review audio provenance and package contents. Perform listening, menu/keyboard and accessibility checks when possible, noting gaps.
4. Merge to `main` after CI passes. Tag that commit with `v<version>` and push the tag.
5. The Release workflow validates the tag, builds and tests on Apple Silicon, packages the app and SHA-256 checksum, then creates a **draft** GitHub Release.
6. Inspect workflow results and assets; publish the draft after review. If workflow failure occurs before creating a draft, rerun after correcting the problem. If a draft already exists, edit it instead of creating a duplicate.

CI tests source builds on Apple Silicon and Intel. The automated downloadable archive currently targets Apple Silicon only. Do not claim universal binary support.

## Signing

Current packages are ad-hoc signed. This verifies bundle consistency locally, but does not identify a verified Apple developer or provide notarization. Gatekeeper can block downloaded builds. Do not recommend globally disabling Gatekeeper or removing quarantine recursively.

Developer ID signing and notarization require the maintainer's Apple Developer credentials and are not configured. If introduced, keep keys/certificates in encrypted GitHub environment secrets, use a temporary keychain, submit via Apple's notary tooling, and staple the approved result before creating the archive. Never commit signing material.

## Repository maintenance

Dependabot proposes weekly Actions updates, including pinned SHAs. CI uses read-only repository access, no persisted checkout credentials, and no `pull_request_target` execution. Only the release job has contents-write permission. Branch protection requires passing build/test checks and resolved conversations. The sole maintainer can merge without a second approver; force pushes and branch deletion are disabled.

No automatic stale-issue closure, auto-merge or scheduled releases are enabled.
