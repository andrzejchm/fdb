import 'package:fdb/core/app_died_exception.dart';
import 'package:fdb/core/commands/ext/ext_models.dart';
import 'package:fdb/core/vm_service.dart';

export 'package:fdb/core/commands/ext/ext_models.dart';

// ---------------------------------------------------------------------------
// Core function
// ---------------------------------------------------------------------------

/// Discovers or invokes VM service extensions registered by the running app.
///
/// - [ExtListInput] — calls `getVM`, unions `extensionRPCs` across all
///   isolates, and returns a sorted, deduplicated list.
/// - [ExtCallInput] — calls `callServiceExtension` on the first isolate that
///   exposes the requested method, forwarding any `--arg` parameters.
///
/// Never throws; all error conditions are represented as sealed result cases.
Future<ExtResult> ext(ExtInput input) async {
  try {
    return switch (input) {
      ExtListInput() => await _list(),
      ExtCallInput(:final method, :final args) => await _call(method, args),
    };
  } on AppDiedException catch (e) {
    return ExtAppDied(logLines: e.logLines, reason: e.reason);
  } catch (e) {
    return ExtError(e.toString());
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

Future<ExtResult> _list() async {
  final isolateIds = await findAllIsolateIds();
  if (isolateIds.isEmpty) return const ExtNoIsolates();

  final extensions = <String>{};
  for (final isolateId in isolateIds) {
    final rpcs = await _extensionRpcsForIsolate(isolateId);
    extensions.addAll(rpcs);
  }

  final sorted = extensions.toList()..sort();
  return ExtListOk(sorted);
}

/// Returns the list of extension RPC names registered by [isolateId],
/// or an empty list when the isolate does not expose any.
Future<List<String>> _extensionRpcsForIsolate(String isolateId) async {
  try {
    final response = await vmServiceCall('getIsolate', params: {'isolateId': isolateId});
    final result = response['result'] as Map<String, dynamic>?;
    if (result == null) return [];

    final rpcs = result['extensionRPCs'] as List<dynamic>?;
    if (rpcs == null) return [];

    return rpcs.whereType<String>().toList();
  } on AppDiedException {
    rethrow;
  } catch (_) {
    // Isolate may have vanished between getVM and getIsolate — skip it.
    return [];
  }
}

Future<ExtResult> _call(String method, Map<String, String> args) async {
  final isolateIds = await findAllIsolateIds();
  if (isolateIds.isEmpty) return const ExtNoIsolates();

  // Try each isolate until one responds successfully.
  Object? lastError;
  for (final isolateId in isolateIds) {
    try {
      final params = <String, dynamic>{'isolateId': isolateId, ...args};
      final response = await vmServiceCall(method, params: params);

      // Check for a JSON-RPC level error first.
      final error = response['error'] as Map<String, dynamic>?;
      if (error != null) {
        final message = error['message'] as String? ?? 'Unknown error';
        // Extract nested detail from data.details when available.
        final data = error['data'];
        if (data is Map<String, dynamic>) {
          final details = data['details'];
          if (details is String && details.isNotEmpty) {
            return ExtRelayedError(details);
          }
        }
        return ExtRelayedError(message);
      }

      final result = response['result'] as Map<String, dynamic>?;
      if (result == null) return ExtCallOk(const {});

      // Remove VM protocol housekeeping fields from the result.
      final copy = Map<String, dynamic>.from(result);
      copy.remove('type');
      return ExtCallOk(copy);
    } on AppDiedException {
      rethrow;
    } catch (e) {
      lastError = e;
      // Try the next isolate.
    }
  }

  return ExtError(lastError?.toString() ?? 'Extension not found on any isolate');
}
