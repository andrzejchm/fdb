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

## One-time Setup

Required before the first automated release. Skip if already done.

### pub.dev

1. Authenticate: `dart pub login`
2. Publish the first version interactively (automated publishing requires at least one manual publish):
   ```bash
   dart pub publish --dry-run   # verify, fix any issues
   dart pub publish              # interactive confirmation
   ```
3. Go to <https://pub.dev/packages/fdb/admin> and enable **Automated publishing**:
   - Provider: GitHub Actions
   - Repository: `andrzejchm/fdb`
   - Tag pattern: `v{{version}}`

### GitHub CLI

Verify `gh` is authenticated: `gh auth status`

## Release Checklist

Copy and track progress:

```
- [ ] Pre-release verification (analyze, unit tests, smoke tests)
- [ ] Determine version bump type (major / minor / patch)
- [ ] Update version in all 4 files (lockstep)
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

Update the version string in all 4 files:

| # | File | What to change |
|---|------|----------------|
| 1 | `lib/constants.dart` | `const version = 'X.Y.Z';` |
| 2 | `pubspec.yaml` | `version: X.Y.Z` |
| 3 | `packages/fdb_helper/pubspec.yaml` | `version: X.Y.Z` |
| 4 | `skills/interacting-with-flutter-apps/SKILL.md` | Version in `## Overview` heading and in the version check blockquote |

### Verify consistency

After editing, confirm all 4 files show the same version:
```bash
grep -r "OLD_VERSION" lib/constants.dart pubspec.yaml packages/fdb_helper/pubspec.yaml skills/interacting-with-flutter-apps/SKILL.md
```
Replace `OLD_VERSION` with the **previous** version to confirm no stale references remain.

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

1. **pub.dev**: Check <https://pub.dev/packages/fdb> shows the new version
2. **Install from pub.dev**:
   ```bash
   dart pub global activate fdb
   fdb --version                 # should print: fdb X.Y.Z
   ```
3. **GitHub release**: Check <https://github.com/andrzejchm/fdb/releases> for the new release with auto-generated notes
4. **Git install still works** (for users pinning to a tag):
   ```bash
   dart pub global activate --source git https://github.com/andrzejchm/fdb.git --git-ref vX.Y.Z
   ```

## Troubleshooting

### pub.dev publish fails in CI

- Verify automated publishing is enabled on <https://pub.dev/packages/fdb/admin>
- Verify tag pattern matches `v{{version}}`
- Verify `pubspec.yaml` version matches the tag (tag `v0.2.0` requires `version: 0.2.0`)
- Check the `id-token: write` permission is set on the publish job

### GitHub release not created

- Verify `contents: write` permission is set on the publish job
- Check `gh` auth in the workflow (uses `github.token` automatically)

### Version mismatch

If any of the 4 version files are out of sync, pub.dev publish may succeed with the wrong version. Always verify with the grep command in the Version Bump section.
