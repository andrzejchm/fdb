import 'dart:io';

import 'package:fdb_helper/src/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fdbHelperVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)?.group(1);

    expect(fdbHelperVersion, version);
  });
}
