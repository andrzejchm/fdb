import 'package:flutter/widgets.dart';

/// Enters [text] into the [EditableText] found within [element]'s subtree.
///
/// Throws if no [EditableText] is found.
Future<void> enterText(Element element, String text) async {
  EditableTextState? editableState;

  void visitor(Element child) {
    if (editableState != null) return;
    if (child is StatefulElement && child.state is EditableTextState) {
      editableState = child.state as EditableTextState;
      return;
    }
    child.visitChildren(visitor);
  }

  // Check the element itself first
  if (element is StatefulElement && element.state is EditableTextState) {
    editableState = element.state as EditableTextState;
  } else {
    element.visitChildren(visitor);
  }

  if (editableState == null) {
    throw Exception('No EditableText found in widget subtree');
  }

  editableState!.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
  WidgetsBinding.instance.scheduleFrame();
}
