import 'dart:io';

import 'package:fdb/constants.dart';

Future<int> runLogs(List<String> args) async {
  String? tag;
  var last = 50;
  var follow = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--tag':
        tag = args[++i];
      case '--last':
        last = int.parse(args[++i]);
      case '--follow':
        follow = true;
    }
  }

  final file = File(logFile);
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
  var offset = file.lengthSync();

  // Print existing content first
  final existing = file.readAsStringSync();
  if (existing.isNotEmpty) {
    final lines = existing.split('\n');
    for (final line in lines) {
      if (tag == null || line.contains(tag)) {
        stdout.writeln(line);
      }
    }
  }

  // Then follow new content
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final currentSize = file.lengthSync();
    if (currentSize > offset) {
      final raf = file.openSync();
      raf.setPositionSync(offset);
      final newBytes = raf.readSync(currentSize - offset);
      raf.closeSync();

      final newContent = String.fromCharCodes(newBytes);
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
