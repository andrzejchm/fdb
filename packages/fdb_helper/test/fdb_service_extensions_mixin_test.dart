import 'dart:developer' as developer;

import 'package:fdb_helper/fdb_helper.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for a third-party binding mixin (e.g. device_preview's
/// `DevicePreviewBindingMixin`) to prove [FdbServiceExtensionsMixin] composes
/// with other [WidgetsBinding] mixins instead of requiring sole ownership of
/// the ambient binding.
mixin _OtherBindingMixin on WidgetsBinding {
  bool otherMixinInitialized = false;

  @override
  void initServiceExtensions() {
    super.initServiceExtensions();
    otherMixinInitialized = true;
  }
}

class _ComposedBinding extends WidgetsFlutterBinding with FdbServiceExtensionsMixin, _OtherBindingMixin {}

void main() {
  // BindingBase only allows one binding to be constructed per isolate, so
  // every test in this file shares the single instance created here.
  late _ComposedBinding binding;

  setUpAll(() {
    binding = _ComposedBinding();
  });

  test('both mixins in the chain run their initServiceExtensions', () {
    // With `with FdbServiceExtensionsMixin, _OtherBindingMixin`, the
    // last-listed mixin is closest to the class, so
    // _OtherBindingMixin.initServiceExtensions runs first; its super call
    // reaches FdbServiceExtensionsMixin further up the "with" chain.
    expect(binding.otherMixinInitialized, isTrue);
  });

  test('FdbServiceExtensionsMixin registers ext.fdb.* extensions on a composed binding', () {
    // registerExtension throws ArgumentError when a name is already taken,
    // so this proves the mixin registered ext.fdb.tap during construction.
    expect(
      () => developer.registerExtension(
        'ext.fdb.tap',
        (String method, Map<String, String> params) async => developer.ServiceExtensionResponse.result('{}'),
      ),
      throwsArgumentError,
    );
  });
}
