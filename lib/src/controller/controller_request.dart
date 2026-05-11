import 'dart:convert';

import 'package:fdb/src/controller/commands/command_request.dart';
import 'package:fdb/src/controller/commands/command_runner.dart';
import 'package:fdb/src/controller/controller_command.dart';
import 'package:fdb/src/controller/controller_context.dart';

abstract class ControllerRequest implements CommandRequest {
  const ControllerRequest({required this.token});
  factory ControllerRequest.fromJsonLine(String line) {
    final json = jsonDecode(line) as Map<String, dynamic>;
    return ControllerRequest.fromJson(json);
  }
  factory ControllerRequest.fromJson(Map<String, dynamic> json) {
    final command = ControllerCommand.fromWireName(json['command'] as String?);
    if (command == null) {
      throw const FormatException('Unknown controller command.');
    }
    return command.readRequest(json);
  }

  @override
  final String token;

  @override
  Map<String, Object?> toJson() => {
        'token': token,
        'command': command.wireName,
      };

  @override
  String toJsonLine() => jsonEncode(toJson());

  CommandRunner createRunner(ControllerContext controller);
}
