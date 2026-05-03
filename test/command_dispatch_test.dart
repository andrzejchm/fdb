import 'package:fdb/cli/adapters/launch_cli.dart';
import 'package:fdb/cli/cli_command.dart';
import 'package:fdb/cli/command_dispatch.dart';
import 'package:test/test.dart';

import '../bin/fdb.dart' as fdb_bin;

void main() {
  group('command dispatch', () {
    const routedCommands = [
      'devices',
      'deeplink',
      'launch',
      'reload',
      'restart',
      'screenshot',
      'logs',
      'syslog',
      'crash-report',
      'tree',
      'describe',
      'doctor',
      'grant-permission',
      'native-tap',
      'tap',
      'longpress',
      'double-tap',
      'input',
      'scroll',
      'scroll-to',
      'wait',
      'swipe',
      'back',
      'clean',
      'shared-prefs',
      'ext',
      'select',
      'selected',
      'mem',
      'gc',
      'status',
      'kill',
      'simulator',
      'skill',
    ];

    test('covers every command advertised in bin/fdb.dart usage', () {
      expect(_advertisedCommands(), routedCommands);
    });

    for (final command in routedCommands) {
      test('$command supports --help through the dispatcher', () async {
        final exitCode = command == 'launch'
            ? await runLaunchCli(['--help'])
            : await runFdbCommand(CliCommand.fromWireName(command)!, ['--help']);
        expect(exitCode, 0);
      });
    }
  });
}

List<String> _advertisedCommands() {
  final commands = <String>[];
  var inCommands = false;
  for (final line in fdb_bin.usage.split('\n')) {
    if (line == 'Commands:') {
      inCommands = true;
      continue;
    }
    if (line == 'Global options:') break;
    if (!inCommands) continue;

    final match = RegExp(r'^  ([a-z][a-z-]*)(?:\s|$)').firstMatch(line);
    if (match != null) {
      commands.add(match.group(1)!);
    }
  }
  return commands;
}
