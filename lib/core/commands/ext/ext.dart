import 'package:fdb/core/commands/ext/ext_models.dart';
import 'package:fdb/src/controller/fdb_controller.dart';

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
    final result = await getIsolate(isolateId);
    return result.extensionRPCs;
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
  String? lastRelayedError;
  for (final isolateId in isolateIds) {
    final response = await (() async {
      try {
        final params = <String, dynamic>{...args, 'isolateId': isolateId};
        return await extCall(method, params: params);
      } on AppDiedException {
        rethrow;
      } catch (e) {
        lastError = e;
        return null;
      }
    })();
    if (response == null) {
      continue;
    }

    if (response.errorCode != null) {
      final message = response.errorMessage ?? 'Unknown error';
      // −32601 = MethodNotFound: the extension is not registered on this isolate.
      // Continue to try the next isolate.
      if (response.errorCode == -32601) {
        lastRelayedError = message;
        continue;
      }
      // Any other error code means the extension was found but its handler
      // failed — return immediately without trying more isolates.
      if (response.errorDetails != null && response.errorDetails!.isNotEmpty) {
        return ExtRelayedError(response.errorDetails!);
      }
      return ExtRelayedError(message);
    }

    return ExtCallOk(response.extensionResult ?? const {});
  }

  if (lastRelayedError != null) return ExtRelayedError(lastRelayedError);
  return ExtError(lastError?.toString() ?? 'Extension not found on any isolate');
}
