/// Whether [latest] is a newer release than [current], decided as the
/// server's `update_check.is_newer` decides it: in PEP 440 order, and false
/// when either is not a version PEP 440 can read.
bool isNewerVersion(String latest, String current) {
  final a = _Pep440.parse(latest);
  final b = _Pep440.parse(current);
  return a != null && b != null && a.compareTo(b) > 0;
}

// packaging.version's VERSION_PATTERN, matched against a lower-cased string.
final _pattern = RegExp(
  r'^v?(?:(\d+)!)?(\d+(?:\.\d+)*)'
  r'(?:[-_.]?(alpha|a|beta|b|preview|pre|c|rc)[-_.]?(\d+)?)?'
  r'(?:-(\d+)|[-_.]?(post|rev|r)[-_.]?(\d+)?)?'
  r'(?:[-_.]?(dev)[-_.]?(\d+)?)?'
  r'(?:\+([a-z0-9]+(?:[-_.][a-z0-9]+)*))?$',
);

const _preRank = {
  'a': 0,
  'alpha': 0,
  'b': 1,
  'beta': 1,
  'c': 2,
  'pre': 2,
  'preview': 2,
  'rc': 2,
};

class _Pep440 implements Comparable<_Pep440> {
  _Pep440(this.epoch, this.release, this.pre, this.post, this.dev, this.local);

  final int epoch;

  /// Without trailing zeros, so 5.16 and 5.16.0 are the same release.
  final List<int> release;

  /// Rank (a, b, rc) and number.
  final List<int>? pre;
  final int? post;
  final int? dev;

  /// Each segment an int or a String.
  final List<Object>? local;

  static _Pep440? parse(String text) {
    final m = _pattern.firstMatch(text.trim().toLowerCase());
    if (m == null) return null;
    int number(int group) => int.parse(m.group(group) ?? '0');
    final release = m.group(2)!.split('.').map(int.parse).toList();
    while (release.isNotEmpty && release.last == 0) {
      release.removeLast();
    }
    final hasPost = m.group(5) != null || m.group(6) != null;
    return _Pep440(
      number(1),
      release,
      m.group(3) == null ? null : [_preRank[m.group(3)]!, number(4)],
      hasPost ? int.parse(m.group(5) ?? m.group(7) ?? '0') : null,
      m.group(8) == null ? null : number(9),
      m
          .group(10)
          ?.split(RegExp(r'[-_.]'))
          .map((s) => int.tryParse(s) ?? s)
          .toList(),
    );
  }

  // A leading rank stands in for packaging's infinities: a dev release with
  // no pre or post release sorts before every pre-release of its release,
  // the final release after them.
  List<int> get _preKey =>
      pre != null ? [1, ...pre!] : [post == null && dev != null ? 0 : 2];
  List<int> get _postKey => post == null ? [0] : [1, post!];
  List<int> get _devKey => dev == null ? [1] : [0, dev!];

  @override
  int compareTo(_Pep440 other) {
    for (final c in [
      epoch.compareTo(other.epoch),
      _compareInts(release, other.release),
      _compareInts(_preKey, other._preKey),
      _compareInts(_postKey, other._postKey),
      _compareInts(_devKey, other._devKey),
    ]) {
      if (c != 0) return c;
    }
    return _compareLocal(local, other.local);
  }
}

int _compareInts(List<int> a, List<int> b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return a.length.compareTo(b.length);
}

/// No local label sorts first; numeric segments sort above text ones.
int _compareLocal(List<Object>? a, List<Object>? b) {
  if (a == null || b == null) return (a == null ? 0 : 1) - (b == null ? 0 : 1);
  for (var i = 0; i < a.length && i < b.length; i++) {
    final c = switch ((a[i], b[i])) {
      (int x, int y) => x.compareTo(y),
      (String x, String y) => x.compareTo(y),
      (int _, String _) => 1,
      _ => -1,
    };
    if (c != 0) return c;
  }
  return a.length.compareTo(b.length);
}
