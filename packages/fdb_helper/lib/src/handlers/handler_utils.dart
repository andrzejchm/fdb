import 'dart:convert';
import 'dart:developer' as developer;

developer.ServiceExtensionResponse errorResponse(String message) {
  return developer.ServiceExtensionResponse.error(
    -32000,
    jsonEncode({'error': message}),
  );
}
