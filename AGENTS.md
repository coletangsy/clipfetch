## Agent skills

### Issue tracker

Issues live in GitHub Issues for `coletangsy/clipfetch`. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the default triage labels, including `ready-for-agent`. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context project. See `docs/agents/domain.md`.

## Release artifacts

- Keep distributable DMGs in `dist/`, named `ClipFetch-v<version>-unsigned.dmg`.
- The v1 DMG is a universal macOS 26+ build that is ad-hoc signed but not notarized.
- Tag a commit already in `main`'s history as `v<version>` to run the GitHub release workflow. It tests, builds, packages, and publishes the matching unsigned DMG.
