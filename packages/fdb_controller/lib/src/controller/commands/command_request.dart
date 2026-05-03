import 'package:fdb_controller/src/controller/controller_command.dart';

abstract class CommandRequest {
  ControllerCommand get command;

  String get token;

  Map<String, Object?> toJson();

  String toJsonLine();
}
