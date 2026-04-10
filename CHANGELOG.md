## 1.0.1

### Fixes
- Fix dartdoc angle bracket warnings in `describe.dart` and `vm_service.dart`
- Fix deeplink smoke test — register `fdbtest://` URL scheme in test app Info.plist
- Fix back smoke test — restart app to reset UI state before navigation test

### Improvements
- Add `example/example.md` for pub.dev Example tab
- Replace mermaid code block with pre-rendered SVG diagram (renders on pub.dev)
- Add `dart pub global activate fdb` install option to README
- Add release skill and CI publish workflow

## 1.0.0

### New commands
- `fdb back` — navigate back via Navigator.maybePop(), handles dialogs and root detection
- `fdb longpress` — long-press widgets, reuses tap infrastructure with configurable duration
- `fdb swipe` — swipe gestures for PageView/Dismissible with widget targeting and smart defaults
- `fdb describe` — compact screen snapshot with interactive element refs (@1, @2...) for agent navigation
- `fdb devices` — list connected devices
- `fdb deeplink` — open deep link URLs on device
- `fdb skill` — print SKILL.md for AI agent consumption

### Describe command
- Shows only hittable, topmost-layer widgets (filters obscured/background route elements)
- Gesture info on GestureDetector/InkWell: `(tap)`, `(tap,horizontalDrag)`, `(tap,longPress)`
- Extracts text from all children, tooltips, and icon semantic labels
- Filters framework widgets and Unicode PUA icon codepoints
- Ref-based tapping: `fdb tap @3` taps the 3rd interactive element from last describe
- Shows deepest route name and Scaffold title

### Fixes
- Error propagation: specific error messages instead of "Server error"
- `--text` tap: walks to hittable ancestor when Text widget itself isn't in hit-test path
- `--index` ordering: user widgets before framework widgets (Overlay, IndexedStack, _Theater)
- `--key` tap: ancestor walk for KeyMatcher/TypeMatcher, not just TextMatcher
- `--help` / `-h`: prints to stdout with exit 0, no "ERROR:" prefix
- Swipe velocity: process-relative Stopwatch timestamps for VelocityTracker fling detection
- Screenshot: defaults to 1x logical resolution (~180KB vs ~1MB), `--full` for native
- Screenshot: supports `--output=path` equals syntax, fixes Android shell escaping
- Skill command: resolves SKILL.md via package URI for global installs

## 0.1.0

- Initial release
- CLI commands: launch, status, reload, restart, kill, logs, tree, screenshot, select, selected, tap, input, scroll
- fdb_helper package for Flutter app integration
