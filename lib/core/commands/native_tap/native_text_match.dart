/// Label matching shared by `fdb native-tap --text` on Android and the iOS
/// simulator. Pure functions only.
library;

/// `--timeout` for `--text` when none is given, same as `fdb tap`.
const defaultNativeTapTextTimeoutSeconds = 5;

/// Pause between two reads of the screen while `--text` waits for a match.
const nativeTapTextPollInterval = Duration(milliseconds: 300);

/// Lowercases and folds typographic variants, so `Don't allow` matches
/// `Don’t allow`: curly quotes become straight ones, no-break spaces become
/// spaces.
String foldNativeLabel(String s) => s
    .replaceAll(RegExp('[\u2018\u2019]'), "'")
    .replaceAll(RegExp('[\u201C\u201D]'), '"')
    .replaceAll('\u00A0', ' ')
    .trim()
    .toLowerCase();

/// [s] with every run of whitespace (newlines included) collapsed to one
/// space, for labels shown on a single output line.
String oneLineLabel(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Outcome of [pickNativeMatch].
sealed class NativeMatchPick<T> {
  const NativeMatchPick();
}

class NativeMatchPicked<T> extends NativeMatchPick<T> {
  const NativeMatchPicked(this.match);
  final T match;
}

/// Several matches and no index.
class NativeMatchAmbiguous<T> extends NativeMatchPick<T> {
  const NativeMatchAmbiguous(this.matches);
  final List<T> matches;
}

/// Nothing to tap: no matches, or the index is past the last one.
class NativeMatchNone<T> extends NativeMatchPick<T> {
  const NativeMatchNone();
}

/// Picks the match to tap: the one at [index] (0-based, screen order, like
/// `fdb tap --index`), or the only match when [index] is null.
NativeMatchPick<T> pickNativeMatch<T>(List<T> matches, {required int? index}) {
  if (matches.isEmpty) return NativeMatchNone<T>();
  if (index != null) {
    return index >= 0 && index < matches.length ? NativeMatchPicked<T>(matches[index]) : NativeMatchNone<T>();
  }
  if (matches.length == 1) return NativeMatchPicked<T>(matches.single);
  return NativeMatchAmbiguous<T>(matches);
}
