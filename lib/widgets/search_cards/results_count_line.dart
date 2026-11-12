import 'package:flutter/material.dart';

import '../../data_model/data_model.dart';
import '../../theme/app_theme.dart';

/// Result counts as one line: "3 artists · 8 albums · 12 tracks". Kinds with
/// none are left out.
String resultCounts(Map<SearchType, int> counts) {
  const nouns = {
    SearchType.artist: ('artist', 'artists'),
    SearchType.album: ('album', 'albums'),
    SearchType.track: ('track', 'tracks'),
    SearchType.playlist: ('playlist', 'playlists'),
  };
  return [
    for (final MapEntry(key: type, value: (one, many)) in nouns.entries)
      if (counts[type] case final count? when count > 0)
        '$count ${count == 1 ? one : many}',
  ].join(' · ');
}

/// Monospace line showing result counts: "3 artists · 8 albums · 12 tracks".
class ResultsCountLine extends StatelessWidget {
  final Map<SearchType, int> counts;

  const ResultsCountLine({super.key, required this.counts});

  @override
  Widget build(BuildContext context) {
    final line = resultCounts(counts);
    if (line.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(line, style: KalinkaTextStyles.resultCountHint),
    );
  }
}
