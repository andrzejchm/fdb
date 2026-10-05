import 'package:fdb/src/controller/commands/command_response.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/commands/shared/fdb_action_response.dart';
import 'package:fdb/src/controller/commands/shared/request.dart';
import 'package:fdb/src/controller/commands/shared/runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';
import 'package:fdb/src/controller/controller_json.dart';
import 'package:fdb/src/controller/vm_service/deserialise.dart';
import 'package:fdb/src/controller/vm_service/vm_service_impl.dart';

class FdbEnterTextCommandRequest extends WidgetSelectorCommandRequest {
  const FdbEnterTextCommandRequest({
    required super.token,
    required super.isolateId,
    this.input,
    this.action,
    this.focused,
    super.text,
    super.key,
    super.type,
    super.index,
  });
  factory FdbEnterTextCommandRequest.fromJson(Map<String, Object?> json) => FdbEnterTextCommandRequest(
        token: ControllerJson.token(json),
        isolateId: ControllerJson.requiredString(json, 'isolateId'),
        input: ControllerJson.optionalString(json, 'input'),
        action: ControllerJson.optionalString(json, 'action'),
        focused: ControllerJson.optionalString(json, 'focused'),
        text: ControllerJson.optionalString(json, 'text'),
        key: ControllerJson.optionalString(json, 'key'),
        type: ControllerJson.optionalString(json, 'type'),
        index: ControllerJson.optionalString(json, 'index'),
      );

  /// Text to enter; null when only [action] is sent.
  final String? input;

  /// Optional IME action name (send, done, newline, ...).
  final String? action;
  final String? focused;

  @override
  ControllerCommand get command => ControllerCommand.fdbEnterText;

  @override
  Map<String, dynamic> toVmParams() => {
        ...super.toVmParams(),
        if (input != null) 'input': input,
        if (action != null) 'action': action,
        if (focused != null) 'focused': focused,
      };

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        if (input != null) 'input': input,
        if (action != null) 'action': action,
        if (focused != null) 'focused': focused,
      };

  @override
  CommandRunner createRunner(ControllerContext controller) => const FdbEnterTextCommandRunner();
}

class FdbEnterTextCommandResponse extends FdbActionCommandResponse {
  const FdbEnterTextCommandResponse({
    required super.status,
    required super.error,
    required super.unexpected,
    required this.widgetType,
    this.clientType,
    this.clientKind,
    this.action,
  });

  factory FdbEnterTextCommandResponse.fromResponse(Map<String, dynamic> response) {
    final result = extensionResultAsMap(response);
    return FdbEnterTextCommandResponse(
      status: result?['status'] as String?,
      error: result?['error'] as String?,
      widgetType: result?['widgetType'] as String?,
      clientType: result?['clientType'] as String?,
      clientKind: result?['clientKind'] as String?,
      action: result?['action'] as String?,
      unexpected: result ?? response,
    );
  }

  final String? widgetType;

  /// State type that received the text, e.g. EditableTextState or QuillRawEditorState.
  final String? clientType;

  /// EditableText, TextInputClient, or DeltaTextInputClient.
  final String? clientKind;

  /// IME action that was performed, if any.
  final String? action;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'widgetType': widgetType,
        'clientType': clientType,
        'clientKind': clientKind,
        'action': action,
      };
}

class FdbEnterTextCommandRunner extends VmServiceCommand<FdbEnterTextCommandRequest> {
  const FdbEnterTextCommandRunner() : super(_execute);
  static Future<CommandResponse> _execute(FdbEnterTextCommandRequest request) async {
    final response = await callVmServiceMethod(
      'ext.fdb.enterText',
      params: request.toVmParams(),
    );
    return FdbEnterTextCommandResponse.fromResponse(response);
  }
}
