import 'dart:io';

import 'package:fdb/core/binstub_sdk_check.dart';

/// Prints one `WARNING:` line to stderr when fdb's launcher was written for
/// another Dart SDK. Never throws and never affects the exit code.
void runBinstubSdkCheckCli() {
  try {
    final line = formatBinstubSdkMismatch(checkBinstubSdk(binstubSdkCheckInputFromPlatform()));
    if (line != null) stderr.writeln(line);
  } catch (_) {
    // Diagnostic only — must never break the actual command.
  }
}

/// The warning for [mismatch], or null when there is none.
String? formatBinstubSdkMismatch(BinstubSdkMismatch? mismatch) => mismatch == null
    ? null
    : "WARNING: fdb was activated with Dart ${mismatch.activated} but 'dart' on PATH is ${mismatch.running}; "
        'that causes the "Can\'t load Kernel binary" line above. '
        "Fix: run 'dart pub global activate fdb' with the Dart you use.";
