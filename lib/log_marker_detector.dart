bool didLogGainMarker({
  required String before,
  required String after,
  required String marker,
}) {
  if (before == after) {
    return false;
  }

  final sharedLength = before.length < after.length ? before.length : after.length;
  var firstDiff = 0;
  while (firstDiff < sharedLength && before.codeUnitAt(firstDiff) == after.codeUnitAt(firstDiff)) {
    firstDiff++;
  }

  final searchStart = firstDiff >= marker.length ? firstDiff - marker.length + 1 : 0;
  return after.substring(searchStart).contains(marker);
}
