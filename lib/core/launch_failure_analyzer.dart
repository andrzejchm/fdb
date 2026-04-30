import 'dart:convert';
import 'dart:math';

typedef LaunchFailureAnalysis = ({
  String category,
  String rootCause,
  List<String> contextLines,
  String? remediationHint,
});

typedef _CategoryHeuristic = ({
  String category,
  List<String> strongTokens,
  List<String> weakTokens,
  String label,
  String remediationHint,

  /// When true, the category is matched against the full log text rather than
  /// only the top signal lines. Use only for categories whose strong tokens are
  /// highly specific (exact Xcode/adb error strings) and would never produce
  /// false positives on an unrelated log.
  bool fullLogScan,
});

LaunchFailureAnalysis analyzeLaunchFailure(
  String output, {
  int maxContextLines = 15,
}) {
  final lines = const LineSplitter().convert(output);

  final signalLineIndexes = _findSignalLineIndexes(lines);
  final primaryIndex = signalLineIndexes.isEmpty ? _findBestFallbackLine(lines) : signalLineIndexes.first;

  final category = _classifyCategory(lines, signalLineIndexes);
  final resolvedHint = _resolveRemediationHint(
    lines,
    category.category,
    category.remediationHint,
  );
  final rootSource = primaryIndex == -1 ? 'flutter process exited unexpectedly' : _cleanLine(lines[primaryIndex]);

  final categoryLabel = _categoryLabel(category.category);
  final rootCause = _buildRootCause(
    lines,
    primaryIndex,
    category.category,
    categoryLabel,
    rootSource,
  );

  final contextIndexes = signalLineIndexes.isEmpty && primaryIndex != -1 ? <int>[primaryIndex] : signalLineIndexes;

  return (
    category: category.category,
    rootCause: rootCause,
    contextLines: _buildContextLines(
      lines,
      contextIndexes,
      maxContextLines: maxContextLines,
    ),
    remediationHint: resolvedHint,
  );
}

String? _resolveRemediationHint(
  List<String> lines,
  String category,
  String? defaultHint,
) {
  if (category != 'IOS_CODESIGN_PROVISIONING') return defaultHint;

  final combined = lines.join('\n').toLowerCase();
  if (!combined.contains('errsecinternalcomponent')) return defaultHint;

  return '$defaultHint Possible locked keychain / SSH non-interactive codesign access. Unlock the login keychain and allow codesign key access for non-interactive sessions.';
}

String _buildRootCause(
  List<String> lines,
  int primaryIndex,
  String category,
  String? categoryLabel,
  String rootSource,
) {
  var source = rootSource;

  if (category == 'IOS_CODESIGN_PROVISIONING' && primaryIndex >= 0) {
    final nearbyErrSec = _findNearbyLineContaining(lines, primaryIndex, 'errsec');
    if (nearbyErrSec != null && !source.toLowerCase().contains('errsecinternalcomponent')) {
      source = '$source (${_cleanLine(nearbyErrSec)})';
    }
  }

  if (categoryLabel == null) return _truncate(source);
  return _truncate('$categoryLabel: $source');
}

String? _findNearbyLineContaining(List<String> lines, int index, String token) {
  final start = max(0, index - 2);
  final end = min(lines.length - 1, index + 2);
  for (var i = start; i <= end; i++) {
    if (lines[i].toLowerCase().contains(token)) return lines[i];
  }
  return null;
}

({String category, String? remediationHint}) _classifyCategory(
  List<String> lines,
  List<int> signalLineIndexes,
) {
  // Build a corpus from the top signal lines. This narrows the search to the
  // most informative lines and avoids noise from verbose flutter output.
  final signalCorpus = <String>[];
  if (signalLineIndexes.isEmpty) {
    signalCorpus.addAll(lines.map((line) => line.toLowerCase()));
  } else {
    for (final index in signalLineIndexes.take(5)) {
      signalCorpus.add(lines[index].toLowerCase());
    }
  }
  final signalJoined = signalCorpus.join('\n');

  // Some categories have highly specific tokens that are never present in
  // unrelated failures (e.g. exact Xcode error strings). For these we also
  // scan the full log so that adjacent high-signal lines (which the proximity
  // deduplication in _findSignalLineIndexes may collapse into one) are not
  // silently dropped from the search window.
  final fullJoined = lines.map((l) => l.toLowerCase()).join('\n');

  var bestCategory = 'UNKNOWN';
  String? bestHint;
  var bestScore = 0;

  for (final heuristic in _categoryHeuristics) {
    final corpus = heuristic.fullLogScan ? fullJoined : signalJoined;
    var score = 0;

    for (final token in heuristic.strongTokens) {
      if (corpus.contains(token)) score += 6;
    }

    for (final token in heuristic.weakTokens) {
      if (corpus.contains(token)) score += 2;
    }

    if (score > bestScore) {
      bestScore = score;
      bestCategory = heuristic.category;
      bestHint = heuristic.remediationHint;
    }
  }

  if (bestScore == 0) {
    return (
      category: 'UNKNOWN',
      remediationHint: 'Inspect the flutter run output above for the first error/failed line near the end.',
    );
  }

  return (category: bestCategory, remediationHint: bestHint);
}

List<int> _findSignalLineIndexes(List<String> lines) {
  final scored = <({int index, int score})>[];

  for (var i = 0; i < lines.length; i++) {
    final score = _lineSignalScore(lines[i]);
    if (score > 0) scored.add((index: i, score: score));
  }

  if (scored.isEmpty) return <int>[];

  scored.sort((a, b) {
    if (a.score != b.score) return b.score.compareTo(a.score);
    return b.index.compareTo(a.index);
  });

  final selected = <int>[];
  for (final candidate in scored) {
    final tooClose = selected.any((index) => (index - candidate.index).abs() <= 1);
    if (tooClose) continue;
    selected.add(candidate.index);
    if (selected.length >= 5) break;
  }

  return selected;
}

int _lineSignalScore(String line) {
  final lower = line.toLowerCase();

  if (lower.trim().isEmpty) return -1;
  if (lower.contains('warning')) return -3;

  var score = 0;
  if (lower.contains('error')) score += 6;
  if (lower.contains('failed')) score += 6;
  if (lower.contains('exception')) score += 5;
  if (lower.contains('unable to')) score += 4;
  if (lower.contains('exit code')) score += 3;
  if (lower.contains('errsec')) score += 6;
  if (lower.contains('codesign')) score += 5;
  if (lower.contains('provision')) score += 4;
  if (lower.contains('phasescriptexecution')) score += 5;
  if (lower.contains('xcodebuild')) score += 4;
  if (lower.contains('adb')) score += 4;
  if (lower.contains('install_failed')) score += 6;
  if (lower.contains('package install error')) score += 6;
  if (lower.contains('android sdk')) score += 5;
  if (lower.contains('flutter doctor')) score += 3;
  if (lower.contains('build failed')) score += 5;
  if (lower.contains('registering bundle identifier')) score += 8;
  if (lower.contains('no account for team')) score += 8;
  if (lower.contains('no profiles for')) score += 6;
  if (lower.contains('your device is locked')) score += 8;
  if (lower.contains('license agreements')) score += 7;
  if (lower.contains('flutter doctor --android-licenses')) score += 6;

  return score;
}

int _findBestFallbackLine(List<String> lines) {
  for (var i = lines.length - 1; i >= 0; i--) {
    final lower = lines[i].toLowerCase();
    if (lower.contains('error') || lower.contains('failed') || lower.contains('exception')) {
      return i;
    }
  }

  for (var i = lines.length - 1; i >= 0; i--) {
    if (lines[i].trim().isNotEmpty) return i;
  }

  return -1;
}

List<String> _buildContextLines(
  List<String> lines,
  List<int> matchIndexes, {
  required int maxContextLines,
}) {
  if (lines.isEmpty) return <String>[];

  if (matchIndexes.isEmpty) {
    final start = max(0, lines.length - maxContextLines);
    return [
      for (var i = start; i < lines.length; i++) 'L${i + 1}: ${lines[i]}',
    ];
  }

  final selected = <int>{};
  final primary = matchIndexes.first;
  final halfWindow = maxContextLines ~/ 2;
  final primaryStart = max(0, primary - halfWindow);
  final primaryEnd = min(lines.length - 1, primary + halfWindow);

  for (var i = primaryStart; i <= primaryEnd; i++) {
    selected.add(i);
  }

  for (final index in matchIndexes.skip(1)) {
    if (selected.length >= maxContextLines) break;
    final start = max(0, index - 1);
    final end = min(lines.length - 1, index + 1);
    for (var i = start; i <= end; i++) {
      selected.add(i);
      if (selected.length >= maxContextLines) break;
    }
  }

  final sorted = _trimContextIndexes(
    selected,
    lines,
    primary,
    maxContextLines,
    requiredIndexes: matchIndexes.toSet(),
  );
  return [
    for (final i in sorted) 'L${i + 1}: ${lines[i]}',
  ];
}

List<int> _trimContextIndexes(
  Set<int> selected,
  List<String> lines,
  int primary,
  int maxContextLines, {
  required Set<int> requiredIndexes,
}) {
  final indexes = selected.toList();
  if (indexes.length <= maxContextLines) {
    indexes.sort();
    return indexes;
  }

  final scored = indexes.map((index) {
    final signal = _lineSignalScore(lines[index]);
    final distance = (index - primary).abs();
    final priority = (signal * 20) - distance;
    return (index: index, priority: priority);
  }).toList();

  scored.sort((a, b) => b.priority.compareTo(a.priority));

  final kept = <int>{};
  for (final index in requiredIndexes) {
    if (selected.contains(index)) kept.add(index);
  }

  for (final candidate in scored) {
    if (kept.length >= maxContextLines) break;
    kept.add(candidate.index);
  }

  final result = kept.toList()..sort();
  if (result.length > maxContextLines) {
    return result.sublist(result.length - maxContextLines);
  }
  return result;
}

String _cleanLine(String line) {
  final withoutAnsi = line.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
  return withoutAnsi.trim();
}

String _truncate(String text, {int maxLength = 220}) {
  final cleaned = _cleanLine(text);
  if (cleaned.length <= maxLength) return cleaned;
  return '${cleaned.substring(0, maxLength - 3)}...';
}

String? _categoryLabel(String category) {
  for (final heuristic in _categoryHeuristics) {
    if (heuristic.category == category) return heuristic.label;
  }
  return null;
}

final _categoryHeuristics = <_CategoryHeuristic>[
  // Matched on exact Xcode xcresult error strings surfaced verbatim by Flutter
  // tool (mac.dart _handleXCResultIssue). Seen in real flutter run output when
  // the bundle ID is already registered to another team.
  // fullLogScan: true because this line is often adjacent to the "No profiles
  // for" line, so proximity deduplication in _findSignalLineIndexes may drop it.
  (
    category: 'IOS_BUNDLE_ID_CLAIMED',
    strongTokens: [
      'failed registering bundle identifier',
      'cannot be registered to your development team because it is not available',
    ],
    weakTokens: ['no profiles for', 'change your bundle identifier'],
    label: 'iOS bundle identifier already claimed',
    remediationHint:
        'Change your bundle identifier in Xcode (Runner target → Signing & Capabilities) to a unique value, or reclaim it at developer.apple.com.',
    fullLogScan: true,
  ),
  // Matched on exact Xcode xcresult error string for a missing/invalid Apple ID.
  // fullLogScan: true because this line is adjacent to the "No profiles for"
  // line, so proximity deduplication may exclude it from the signal corpus.
  (
    category: 'IOS_NO_ACCOUNT_FOR_TEAM',
    strongTokens: ['no account for team', 'add a new account in accounts settings'],
    weakTokens: ['verify that your accounts have valid credentials', 'no profiles for'],
    label: 'No Apple ID account found for Xcode team',
    remediationHint: 'Open Xcode → Settings → Accounts, add or re-authenticate the Apple ID for this team.',
    fullLogScan: true,
  ),
  // Matched on exact Flutter tool strings from code_signing.dart /
  // ios_deploy.dart. Covers errSecInternalComponent (bad keychain),
  // Error 0xe8008015 / 0xe8000067 (no provisioning profile via ios-deploy),
  // and the "Failed to codesign … with identity" xcodebuild line.
  (
    category: 'IOS_CODESIGN_PROVISIONING',
    strongTokens: ['codesign', 'errsec', 'provisioning profile'],
    weakTokens: ['signing identity', 'development team', 'no signing certificate'],
    label: 'iOS codesigning/provisioning failed',
    remediationHint: 'Open iOS Signing & Capabilities and verify team, certificate, and provisioning profile.',
    fullLogScan: false,
  ),
  // Matched on exact Flutter tool strings from ios_deploy.dart
  // (deviceLockedError = 'e80000e2', deviceLockedErrorMessage).
  (
    category: 'IOS_DEVICE_LOCKED',
    strongTokens: ['your device is locked', 'e80000e2', 'the device was not, or could not be, unlocked'],
    weakTokens: ['unlock your device'],
    label: 'iOS device is locked',
    remediationHint: 'Unlock the device, then rerun `fdb launch`.',
    fullLogScan: false,
  ),
  // Matched on exact Xcode build output strings (PhaseScriptExecution /
  // xcodebuild failed with exit code 65 / Failed to build iOS app).
  // "failed to build ios app" is iOS-specific and does not appear in Android
  // Gradle failures, preventing false positives from "xcodebuild failed"
  // being a substring of no other context.
  (
    category: 'IOS_BUILD_SCRIPT',
    strongTokens: ['phasescriptexecution', 'xcodebuild failed', 'failed to build ios app'],
    weakTokens: ['[cp] embed pods frameworks', 'command phasescriptexecution failed'],
    label: 'iOS/Xcode build script failed',
    remediationHint: 'Inspect the failing Xcode script phase in the flutter run output above or rerun from Xcode for full script output.',
    fullLogScan: false,
  ),
  // Matched on exact Flutter tool string from android_device.dart
  // ("Package install error: Failure [INSTALL_FAILED_*]") and raw adb output
  // ("adb: failed to install … Failure [INSTALL_FAILED_*]").
  (
    category: 'ANDROID_INSTALL_ADB',
    strongTokens: ['install_failed', 'adb: failed to install', 'package install error'],
    weakTokens: ['performing streamed install', 'error: adb exited with exit code'],
    label: 'Android install/adb failed',
    remediationHint: 'Check `adb devices`, reconnect the device, and uninstall conflicting app versions if needed.',
    fullLogScan: false,
  ),
  // Matched on exact Gradle error string detected by Flutter tool
  // (gradle_errors.dart licenseNotAcceptedHandler).
  (
    category: 'ANDROID_LICENSE_NOT_ACCEPTED',
    strongTokens: [
      'you have not accepted the license agreements of the following sdk components',
      'flutter doctor --android-licenses',
    ],
    weakTokens: ['license agreements'],
    label: 'Android SDK license not accepted',
    remediationHint: 'Run `flutter doctor --android-licenses` to accept the required SDK licenses.',
    fullLogScan: false,
  ),
  // Matched on exact Flutter tool strings from user_messages.dart
  // ("Unable to locate Android SDK") and sdk_toolchain fixture.
  (
    category: 'SDK_TOOLCHAIN',
    strongTokens: ['android sdk not found', 'unable to locate android sdk', 'command not found: flutter'],
    weakTokens: ['android_home', 'flutter doctor', 'xcode not installed', 'cocoapods not installed'],
    label: 'Missing SDK/toolchain dependency',
    remediationHint: 'Install or repair required SDK/toolchain components, then run `flutter doctor -v`.',
    fullLogScan: false,
  ),
  // Matched on Flutter tool strings for Dart/Gradle compile errors.
  // "gradle task assembledebug failed" and "build failed with an exception" are
  // Gradle-specific strings that do not appear in Xcode failures.
  // "target kernel_snapshot_program failed" is from the Dart front-end.
  (
    category: 'FLUTTER_BUILD',
    strongTokens: [
      'gradle task assembledebug failed',
      'gradle task assemblerelease failed',
      'build failed with an exception',
      'target kernel_snapshot_program failed',
    ],
    weakTokens: ['compilation failed', 'execution failed for task', 'error launching application'],
    label: 'Flutter build failed',
    remediationHint: 'Fix the first compile/build error in the flutter run output above before addressing follow-up failures.',
    fullLogScan: false,
  ),
];
