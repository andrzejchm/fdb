import 'dart:convert';
import 'dart:io';

import 'package:fdb/constants.dart';
import 'package:fdb/process_utils.dart';

Future<int> runLogs(List<String> args) async {
  String? deviceId;
  String? tag;
  var last = 50;
  var follow = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--device':
        deviceId = args[++i];
      case '--tag':
        tag = args[++i];
      case '--last':
        final parsed = int.tryParse(args[++i]);
        if (parsed == null) {
          stderr.writeln('ERROR: --last requires an integer value');
          return 1;
        }
        last = parsed;
      case '--follow':
        follow = true;
    }
  }

  final session = resolveSession(deviceId);
  if (session == null) return 1;
  final device = session['deviceId'] as String;

  final file = File(logPath(device));
  if (!file.existsSync()) {
    stderr.writeln('ERROR: Log file not found. Is the app running?');
    return 1;
  }

  if (follow) {
    return _followLogs(file, tag);
  }

  final lines = file.readAsLinesSync();
  final tagFilter = tag;
  var filtered = tagFilter != null
      ? lines.where((l) => l.contains(tagFilter)).toList()
      : lines;

  // Show last N lines
  if (filtered.length > last) {
    filtered = filtered.sublist(filtered.length - last);
  }

  for (final line in filtered) {
    stdout.writeln(line);
  }

  return 0;
}

Future<int> _followLogs(File file, String? tag) async {
  // Print existing content first, then set offset to the actual bytes read
  final existing = file.readAsStringSync();
  if (existing.isNotEmpty) {
    final lines = existing.split('\n');
    for (final line in lines) {
      if (tag == null || line.contains(tag)) {
        stdout.writeln(line);
      }
    }
  }
  var offset = utf8.encode(existing).length;

  // Then follow new content
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final currentSize = file.lengthSync();
    if (currentSize > offset) {
      final raf = file.openSync();
      final List<int> newBytes;
      try {
        raf.setPositionSync(offset);
        newBytes = raf.readSync(currentSize - offset);
      } finally {
        raf.closeSync();
      }

      final newContent = utf8.decode(newBytes, allowMalformed: true);
      final lines = newContent.split('\n');
      for (final line in lines) {
        if (line.isEmpty) continue;
        if (tag == null || line.contains(tag)) {
          stdout.writeln(line);
        }
      }
      offset = currentSize;
    }
  }
}
