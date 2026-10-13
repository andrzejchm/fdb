import 'dart:io';

import 'package:args/args.dart';
import 'package:fdb/cli/args_helpers.dart';
import 'package:fdb/core/commands/native_swipe/native_swipe.dart';

Future<int> runNativeSwipeCli(List<String> args) {
  final parser = ArgParser()
    ..addOption('from', help: 'Required start x,y: iOS points, Android physical pixels; current orientation.')
    ..addOption('to', help: 'Required end x,y in the same coordinate frame.')
    ..addOption('duration', help: 'Required integer milliseconds (1-60000), nominal down-to-up duration.');
  return runCliAdapter(parser, args, _execute);
}

Future<int> _execute(ArgResults results) async {
  for (final name in ['from', 'to', 'duration']) {
    if (results.option(name) == null) {
      stderr.writeln('ERROR: --$name is required');
      return 1;
    }
  }
  if (results.rest.isNotEmpty) {
    stderr.writeln('ERROR: Unexpected positional arguments: ${results.rest.join(' ')}');
    return 1;
  }
  final from = parseXY(results.option('from')!);
  final to = parseXY(results.option('to')!);
  if (from == null || to == null) {
    stderr.writeln('ERROR: Invalid --from or --to value. Expected format: x,y (e.g. 200,400).');
    return 1;
  }
  final duration = int.tryParse(results.option('duration')!);
  if (duration == null) {
    stderr.writeln('ERROR: --duration must be an integer from 1 to 60000 milliseconds.');
    return 1;
  }
  final result = await nativeSwipe((fromX: from.$1, fromY: from.$2, toX: to.$1, toY: to.$2, durationMs: duration));
  switch (result) {
    case NativeSwipeSuccess(:final platform, :final input):
      stdout.writeln('NATIVE_SWIPED=$platform FROM=${input.fromX},${input.fromY} '
          'TO=${input.toX},${input.toY} DURATION_MS=${input.durationMs}');
      return 0;
    case NativeSwipeError(:final message):
      stderr.writeln('ERROR: $message');
      return 1;
  }
}
