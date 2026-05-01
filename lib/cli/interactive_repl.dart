import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/cli/command_dispatch.dart';
import 'package:fdb/core/app_died_exception.dart';

const _help = '''
Interactive fdb commands:
  h, help             Show this help
  r, reload           Hot reload
  R, restart          Hot restart
  d, describe         Describe the current screen
  s, status           Show session status
  kill                Stop the app and exit
  q, quit             Stop the app and exit
  detach              Leave the app running and exit this REPL

You can also run normal fdb commands:
  tap @1
  tap --text Jobs
  input --key search "roof repair"
  scroll down
  back
  logs --last 50
  doctor
  screenshot
  tree --depth 5
  ext list
  mem
  gc
''';

Future<int> runInteractiveRepl() async {
  stdout.write('''
Type 'help' for all commands.

Common commands:
  h, help       Show command help
  s, status     Show whether the app is running
  d, describe   Describe the current screen and refs
  tap @1        Tap an element from describe output
  back          Navigate back
  r, reload     Hot reload
  R, restart    Hot restart
  kill          Stop the app and exit
  detach        Exit this REPL and leave the app running
  q, quit       Stop the app and exit

''');

  while (true) {
    stdout.write('fdb> ');
    await stdout.flush();

    final line = stdin.readLineSync(encoding: utf8);
    if (line == null) {
      stdout.writeln();
      return 0;
    }

    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    List<String> parts;
    try {
      parts = splitCommandLine(trimmed);
    } on FormatException catch (e) {
      stderr.writeln('ERROR: ${e.message}');
      continue;
    }
    if (parts.isEmpty) continue;

    final command = _expandAlias(parts.first);
    final args = parts.sublist(1);

    switch (command) {
      case 'help':
        stdout.write(_help);
        continue;
      case 'detach':
        stdout.writeln('DETACHED');
        return 0;
      case 'kill':
      case 'quit':
        final exitCode = await _runCommand('kill', const []);
        return exitCode;
      case 'launch':
        stderr.writeln('ERROR: launch is not available inside an active session.');
        continue;
    }

    await _runCommand(command, args);
  }
}

String _expandAlias(String command) {
  switch (command) {
    case 'h':
      return 'help';
    case 'r':
      return 'reload';
    case 'R':
      return 'restart';
    case 'd':
      return 'describe';
    case 's':
      return 'status';
    case 'q':
      return 'quit';
    default:
      return command;
  }
}

Future<int> _runCommand(String command, List<String> args) async {
  try {
    return await runFdbCommand(command, args);
  } on AppDiedException catch (e) {
    formatAppDied(e);
    return 1;
  } catch (e) {
    stderr.writeln('ERROR: $e');
    return 1;
  }
}

List<String> splitCommandLine(String input) {
  final args = <String>[];
  final current = StringBuffer();
  String? quote;
  var escaping = false;

  for (var i = 0; i < input.length; i++) {
    final char = input[i];

    if (escaping) {
      current.write(char);
      escaping = false;
      continue;
    }

    if (char == '\\') {
      escaping = true;
      continue;
    }

    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        current.write(char);
      }
      continue;
    }

    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }

    if (char.trim().isEmpty) {
      if (current.length > 0) {
        args.add(current.toString());
        current.clear();
      }
      continue;
    }

    current.write(char);
  }

  if (escaping) {
    current.write('\\');
  }
  if (quote != null) {
    throw const FormatException('Unterminated quoted string');
  }
  if (current.length > 0) {
    args.add(current.toString());
  }

  return args;
}
