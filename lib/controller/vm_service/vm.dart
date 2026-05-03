class VM {
  const VM({
    required this.isolates,
    this.name,
    this.pid,
  });

  final String? name;
  final int? pid;
  final List<String> isolates;

  static VM? fromResponse(Map<String, dynamic> response) {
    final result = response['result'] as Map<String, dynamic>?;

    if (result == null) return null;

    if (response['error'] != null) return null;

    final name = result['name'] as String?;
    final pid = result['pid'] as int?;

    final isolatesMap = result['isolates'] as List<dynamic>?;

    List<String> isolates;

    if (isolatesMap == null || isolatesMap.isEmpty) {
      isolates = <String>[];
    } else {
      isolates = isolatesMap
          .map((i) => (i as Map<String, dynamic>)['id'] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toList();
    }

    return VM(
      name: name,
      pid: pid,
      isolates: isolates,
    );
  }
}
