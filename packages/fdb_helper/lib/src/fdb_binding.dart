import 'package:flutter/widgets.dart';

import 'fdb_service_extensions_mixin.dart';

/// A custom binding that registers VM service extensions for widget interaction.
///
/// Usage in `main()`:
/// ```dart
/// void main() {
///   FdbBinding.ensureInitialized();
///   runApp(const MyApp());
/// }
/// ```
///
/// The extensions registered and the VM service URI broadcast behavior are
/// documented on [FdbServiceExtensionsMixin], which this binding applies.
class FdbBinding extends WidgetsFlutterBinding with FdbServiceExtensionsMixin {
  FdbBinding._();

  static FdbBinding? _instance;

  /// Returns the singleton [FdbBinding], creating it on first call.
  static FdbBinding ensureInitialized() {
    if (_instance == null) {
      FdbBinding._();
    }
    return _instance!;
  }

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
  }
}
