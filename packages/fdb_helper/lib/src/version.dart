/// The fdb_helper package version. Keep in sync with `pubspec.yaml`
/// (`test/version_test.dart` fails when they drift).
///
/// Reported by `ext.fdb.lifecycle` and `ext.fdb.describe` so the fdb CLI can
/// tell when the running app was built with a different fdb_helper than the
/// project now resolves (hot reload/restart does not swap it).
const fdbHelperVersion = '1.13.1';
