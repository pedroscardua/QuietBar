# Contributing

Issues and pull requests in English or Portuguese are welcome. Start an issue before a large redesign; small fixes can go straight to a PR.

1. Fork and create a descriptive branch from `main`.
2. Make a focused change; update user-facing docs when behavior changes.
3. Run `./build.sh`, `./Tests/run_background_checks.sh`, and `python3 scripts/check_repository.py`.
4. Explain the problem, resulting behavior, testing and remaining limitations in the PR.

Use Swift/AppKit for native UI and C11 for the realtime mixer. Avoid allocations, locks, I/O or Objective-C calls in the render callback. Keep runtime dependencies minimal. New audio must be generated here or have explicit redistributable licensing and provenance. Never commit personal presets, recordings, credentials, build outputs or signing keys.

Use four spaces for new code, two for YAML, LF line endings and descriptive names. Existing compact code can be improved incrementally; avoid unrelated reformatting. Tests must stay silent and use isolated state. Add behavioral tests for fixes; UI changes also need manual keyboard and accessibility checks when possible.

Commits need clear imperative subjects; Conventional Commits are welcome but not required. By contributing, you agree to license your contribution under the repository's MIT license. No CLA is required. Maintainers review and squash merges; bot updates are not auto-merged.
