import 'dart:io';

import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/native_button/native_button.dart';

Future<int> runNativeButtonCli(List<String> args) {
  return runSimpleCliAdapter(args, _execute,
      helpText: 'Usage: fdb native-button home|lock\n'
          'One hardware button press on the session Android device or iOS simulator; no VM required.\n'
          'Home goes to OS home when unlocked, not universal unlock.\n'
          'Lock presses power/lock: may sleep or wake depending on screen state. No passcode unlock.');
}

Future<int> _execute(List<String> args) async {
  if (args.length != 1 || !['home', 'lock'].contains(args.single)) {
    stderr.writeln('ERROR: Expected one button: home or lock.');
    return 1;
  }
  switch (await nativeButton((button: args.single))) {
    case NativeButtonSuccess(:final platform, :final button):
      stdout.writeln('NATIVE_BUTTON=$button PLATFORM=$platform');
      return 0;
    case NativeButtonError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
