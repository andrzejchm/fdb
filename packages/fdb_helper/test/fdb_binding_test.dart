import 'dart:developer' as developer;

import 'package:fdb_helper/fdb_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ensureInitialized returns the same singleton instance on repeated calls', () {
    final first = FdbBinding.ensureInitialized();
    final second = FdbBinding.ensureInitialized();

    expect(second, same(first));
  });

  test('ensureInitialized registers ext.fdb.* service extensions via FdbServiceExtensionsMixin', () {
    FdbBinding.ensureInitialized();

    // registerExtension throws ArgumentError when a name is already taken,
    // so this proves FdbBinding registered ext.fdb.describe on init.
    expect(
      () => developer.registerExtension(
        'ext.fdb.describe',
        (String method, Map<String, String> params) async => developer.ServiceExtensionResponse.result('{}'),
      ),
      throwsArgumentError,
    );
  });
}
