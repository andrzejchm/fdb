import 'package:fdb/src/controller/controller_request.dart';

abstract class IsolateIdCommandRequest extends ControllerRequest {
  const IsolateIdCommandRequest({
    required super.token,
    required this.isolateId,
  });

  final String isolateId;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'isolateId': isolateId,
      };
}

abstract class WidgetSelectorCommandRequest extends IsolateIdCommandRequest {
  const WidgetSelectorCommandRequest({
    required super.token,
    required super.isolateId,
    this.text,
    this.key,
    this.type,
    this.index,
    this.x,
    this.y,
    this.ref,
  });

  final String? text;
  final String? key;
  final String? type;
  final String? index;
  final String? x;
  final String? y;

  /// Id of an `fdb describe` ref (`@N`). fdb_helper resolves it to the widget
  /// it names; an fdb_helper without refs rejects the request.
  final String? ref;

  Map<String, dynamic> toVmParams() => {
        'isolateId': isolateId,
        if (text != null) 'text': text,
        if (key != null) 'key': key,
        if (type != null) 'type': type,
        if (index != null) 'index': index,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (ref != null) 'ref': ref,
      };

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        if (text != null) 'text': text,
        if (key != null) 'key': key,
        if (type != null) 'type': type,
        if (index != null) 'index': index,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (ref != null) 'ref': ref,
      };
}

abstract class ObjectGroupCommandRequest extends IsolateIdCommandRequest {
  const ObjectGroupCommandRequest({
    required super.token,
    required super.isolateId,
    required this.objectGroup,
  });

  final String objectGroup;

  @override
  Map<String, Object?> toJson() => {
        ...super.toJson(),
        'objectGroup': objectGroup,
      };
}
