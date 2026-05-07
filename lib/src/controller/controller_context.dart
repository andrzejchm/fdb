abstract class ControllerContext {
  bool get running;

  String? get vmServiceUri;

  String requireAppId();

  void requestStop();

  Future<Map<String, dynamic>> sendFlutterRequest(
    String method,
    Map<String, Object?> params,
  );
}
