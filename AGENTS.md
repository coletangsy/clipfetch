## Agent skills

### Issue tracker

Issues live in GitHub Issues for `coletangsy/clipfetch`. See `docs/agents/issue-tracker.md`.

### Triage labels

Uses the default triage labels, including `ready-for-agent`. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context project. See `docs/agents/domain.md`.

## Teaching materials

- The Swift/macOS lesson lives at `lessons/0001-build-a-macos-app-with-swift.html` and uses `assets/lesson.css`.
- Keep English and Traditional Chinese in the same HTML file; the `zhHant` map drives the language switch.
- After editing the lesson script, run `awk '/<script>/{inside=1; next} /<\/script>/{inside=0} inside' lessons/0001-build-a-macos-app-with-swift.html | node --check` and verify both languages in a browser.

## Release artifacts

- Keep distributable DMGs in `dist/`, named `ClipFetch-v<version>-unsigned.dmg`.
- The v1 DMG is a universal macOS 26+ build that is ad-hoc signed but not notarized.
- In GitHub's Release UI, create a `v<version>` tag targeting `main`, then publish the release. It runs the release workflow; no separate tag push is needed. The workflow tests, builds, packages, and uploads the matching unsigned DMG.
