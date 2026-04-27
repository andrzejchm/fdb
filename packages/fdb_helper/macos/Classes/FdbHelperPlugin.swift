import Cocoa
import FlutterMacOS

public class FdbHelperPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    NativeTapApiSetup.setUp(binaryMessenger: registrar.messenger, api: FdbHelperNativeTapImpl())
  }
}
