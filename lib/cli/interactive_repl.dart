import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fdb/cli/cli_command.dart';
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

    final commandName = _expandAlias(parts.first);
    final args = parts.sublist(1);

    final metaCommand = _replMetaCommands[commandName];
    if (metaCommand != null) {
      final exitCode = await metaCommand(args);
      if (exitCode != null) return exitCode;
      continue;
    }

    final command = CliCommand.fromWireName(commandName);
    if (command == null) {
      stderr.writeln('ERROR: Unknown command: $commandName');
      continue;
    }
    await _runCommand(command, args);
  }
}

typedef _ReplMetaCommand = Future<int?> Function(List<String> args);

final _replAliases = <String, String>{
  'h': 'help',
  'r': 'reload',
  'R': 'restart',
  'd': 'describe',
  's': 'status',
  'q': 'quit',
};

final _replMetaCommands = <String, _ReplMetaCommand>{
  'help': (_) async {
    stdout.write(_help);
    return null;
  },
  'detach': (_) async {
    stdout.writeln('DETACHED');
    return 0;
  },
  'kill': (_) => _runCommand(CliCommand.kill, const []),
  'quit': (_) => _runCommand(CliCommand.kill, const []),
  'launch': (_) async {
    stderr.writeln('ERROR: launch is not available inside an active session.');
    return null;
  },
};

String _expandAlias(String command) => _replAliases[command] ?? command;

Future<int> _runCommand(CliCommand command, List<String> args) async {
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
