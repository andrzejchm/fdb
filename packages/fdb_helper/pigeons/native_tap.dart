import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/native_tap.g.dart',
    swiftOut: 'ios/Classes/NativeTap.g.swift',
    kotlinOut: 'android/src/main/kotlin/io/fdb/fdb_helper/NativeTap.g.kt',
    kotlinOptions: KotlinOptions(package: 'io.fdb.fdb_helper'),
  ),
)
@HostApi()
abstract class NativeTapApi {
  void nativeTap(double x, double y);
}
