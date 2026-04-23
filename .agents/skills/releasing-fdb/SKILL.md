---
name: releasing-fdb
description: Prepares and publishes new fdb releases. Covers version bumping (fdb + fdb_helper lockstep), pre-release verification (smoke tests, analysis), pub.dev publishing, git tagging, and GitHub release creation. Use when bumping the version, preparing a release, publishing to pub.dev, creating a GitHub release, or tagging a new version.
metadata:
  internal: true
---

## Semver

Follow [Semantic Versioning](https://semver.org):
- **Patch** (0.1.x): bug fixes, no API/CLI changes
- **Minor** (0.x.0): new commands, new flags, backward-compatible changes
- **Major** (x.0.0): breaking changes to CLI interface, fdb_helper API, or file contracts

## Prerequisites

- `fdb` published on pub.dev: <https://pub.dev/packages/fdb>
- `fdb_helper` published on pub.dev: <https://pub.dev/packages/fdb_helper>
- Automated publishing enabled for **both** packages on their respective pub.dev admin pages (GitHub Actions, `andrzejchm/fdb`, tag pattern `v{{version}}`, push events):
  - <https://pub.dev/packages/fdb/admin>
  - <https://pub.dev/packages/fdb_helper/admin>
- `LICENSE`, `CHANGELOG.md`, and `README.md` present in both repo root and `packages/fdb_helper/`
- `gh` CLI authenticated: `gh auth status`

## Release Checklist

Copy and track progress:

```
- [ ] Pre-release verification (analyze, unit tests, smoke tests)
- [ ] Determine version bump type (major / minor / patch)
- [ ] Update version in all 10 files (lockstep): constants.dart, pubspec.yaml, fdb_helper/pubspec.yaml, SKILL.md, CHANGELOG.md, fdb_helper/CHANGELOG.md, README.md, example/example.md, doc/README.agents.md (fdb_helper version in snippets)
- [ ] Verify no stale OLD_VERSION references remain (grep check)
- [ ] Commit: `chore: bump version to X.Y.Z`
- [ ] Tag: `git tag vX.Y.Z`
- [ ] Push: `git push origin main --tags`
- [ ] Verify CI workflow passes (analyze, unit tests, pub.dev publish, GitHub release)
- [ ] Post-release verification
```

## Pre-release Verification

**All checks must pass before proceeding. Do not skip any step.**

```bash
task analyze                  # dart analyze + dart format --set-exit-if-changed
task test:unit                # unit tests
task smoke                    # full integration smoke test (requires device/simulator)
```

If `task smoke` fails, fix the issue and re-run before continuing. A connected iOS Simulator or Android emulator is required.

Ensure `main` is clean:
```bash
git status                    # no uncommitted changes
git pull origin main          # up to date with remote
```

## Version Bump

fdb and fdb_helper are versioned in **lockstep** — always bump both to the same version.

**Every release MUST include a version bump.** Update the version string in all 10 files:

| # | File | What to change |
|---|------|----------------|
| 1 | `lib/constants.dart` | `const version = 'X.Y.Z';` |
| 2 | `pubspec.yaml` | `version: X.Y.Z` |
| 3 | `packages/fdb_helper/pubspec.yaml` | `version: X.Y.Z` |
| 4 | `skills/using-fdb/SKILL.md` | Version in `## Overview` heading and in the version check blockquote |
| 5 | `CHANGELOG.md` | Add a `## X.Y.Z` section at the top with a summary of changes since the last release |
| 6 | `packages/fdb_helper/CHANGELOG.md` | Add a `## X.Y.Z` section at the top with a summary of fdb_helper changes (or "no functional changes" if none) |
| 7 | `README.md` | `fdb_helper: ^X.Y.Z` in the dev_dependencies snippet |
| 8 | `example/example.md` | `fdb_helper: ^X.Y.Z` in the dev_dependencies snippet |
| 9 | `doc/README.agents.md` | `fdb_helper: ^X.Y.Z` in the dev_dependencies snippet |
| 10 | `skills/using-fdb/SKILL.md` | `fdb_helper: ^X.Y.Z` in the setup snippet (same file as #4, two separate changes) |

### CHANGELOG.md format

```markdown
## X.Y.Z

### New commands
- `fdb <command>` — description

### Fixes
- Description of fix

### Breaking changes (major only)
- Description
```

Use conventional commit messages from `git log` to build the changelog. Group by: new commands, improvements, fixes, breaking changes. Omit empty groups.

### Verify consistency

After editing, confirm all files show the same version and no stale references remain:
```bash
grep -r "OLD_VERSION" lib/constants.dart pubspec.yaml packages/fdb_helper/pubspec.yaml skills/using-fdb/SKILL.md CHANGELOG.md packages/fdb_helper/CHANGELOG.md README.md example/example.md doc/README.agents.md
```
Replace `OLD_VERSION` with the **previous** version — the command should match ONLY the `CHANGELOG.md` entry for the old release, nowhere else.

## Commit, Tag, Push

```bash
git add -A
git commit -m "chore: bump version to X.Y.Z"
git tag vX.Y.Z
git push origin main --tags
```

The tag push triggers `.github/workflows/publish.yml` which:
1. Runs `dart analyze` and `dart format --set-exit-if-changed`
2. Runs `dart test`
3. Publishes to pub.dev (`dart pub publish --force`)
4. Generates release notes from conventional commits since the previous tag
5. Creates a GitHub release with the generated notes

## Post-release Verification

After CI completes:

1. **fdb on pub.dev**: Check <https://pub.dev/packages/fdb> shows the new version
2. **fdb_helper on pub.dev**: Check <https://pub.dev/packages/fdb_helper> shows the new version
3. **Install from pub.dev**:
   ```bash
   dart pub global activate fdb
   fdb --version                 # should print: fdb X.Y.Z
   ```
4. **GitHub release**: Check <https://github.com/andrzejchm/fdb/releases> for the new release with auto-generated notes
5. **Git install still works** (for users pinning to a tag):
   ```bash
   dart pub global activate --source git https://github.com/andrzejchm/fdb.git --git-ref vX.Y.Z
   ```

## Troubleshooting

### pub.dev publish fails in CI

- Verify automated publishing is enabled on **both** admin pages:
  - <https://pub.dev/packages/fdb/admin>
  - <https://pub.dev/packages/fdb_helper/admin>
- Verify tag pattern matches `v{{version}}` on both
- Verify `pubspec.yaml` version in both packages matches the tag
- Check the `id-token: write` permission is set on the publish job

### GitHub release not created

- Verify `contents: write` permission is set on the publish job
- Check `gh` auth in the workflow (uses `github.token` automatically)

### Version mismatch

If any of the 5 version files are out of sync, pub.dev publish may succeed with the wrong version. Always verify with the grep command in the Version Bump section.
