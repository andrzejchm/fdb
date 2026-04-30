import 'dart:io';
import 'dart:convert';
import 'dart:math';

void main() {
  final content = File('test/fixtures/launch_failures/ios_no_account_for_team.log').readAsStringSync();
  final lines = const LineSplitter().convert(content);
  
  print('=== Signal line scores ===');
  for (var i = 0; i < lines.length; i++) {
    final s = _score(lines[i]);
    if (s != 0) print('L$i (score=$s): ${lines[i]}');
  }
  
  print('\n=== Token checks in joined corpus ===');
  // Simulate what _classifyCategory does
  final signalIndexes = _findSignalIndexes(lines);
  print('Signal indexes: $signalIndexes');
  
  final corpus = <String>[];
  for (final idx in signalIndexes.take(25)) {
    corpus.add(lines[idx].toLowerCase());
  }
  final joined = corpus.join('\n');
  print('Corpus:\n$joined\n');
  
  final tokens = [
    'no account for team',
    'add a new account in accounts settings',
    'provisioning profile',
    'codesign',
    'errsec',
  ];
  for (final t in tokens) {
    print('  "$t" in corpus: ${joined.contains(t)}');
  }
}

int _score(String line) {
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

List<int> _findSignalIndexes(List<String> lines) {
  final scored = <({int index, int score})>[];
  for (var i = 0; i < lines.length; i++) {
    final s = _score(lines[i]);
    if (s > 0) scored.add((index: i, score: s));
  }
  if (scored.isEmpty) return [];
  scored.sort((a, b) {
    if (a.score != b.score) return b.score.compareTo(a.score);
    return b.index.compareTo(a.index);
  });
  final selected = <int>[];
  for (final c in scored) {
    final tooClose = selected.any((idx) => (idx - c.index).abs() <= 1);
    if (tooClose) continue;
    selected.add(c.index);
    if (selected.length >= 5) break;
  }
  return selected;
}
