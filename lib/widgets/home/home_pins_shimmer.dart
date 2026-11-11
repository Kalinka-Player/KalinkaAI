import 'package:flutter/material.dart';

import '../loading_shimmer.dart';
import 'home_layout.dart';

/// One stable placeholder for the whole pin area, independent of the saved
/// previews and the intermediate shapes discovered while they load.
class HomePinsShimmer extends StatelessWidget {
  const HomePinsShimmer({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading pinned items',
    child: ShimmerPulse(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / 180).floor().clamp(2, 4);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var section = 0; section < 2; section++) ...[
                const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ShimmerBlock(width: 144, height: 14),
                ),
                const SizedBox(height: kHomeHeadingGap),
                Row(
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShimmerBlock(height: 120),
                            SizedBox(height: 12),
                            FractionallySizedBox(
                              widthFactor: 0.7,
                              child: ShimmerBlock(height: 12),
                            ),
                            SizedBox(height: 8),
                            FractionallySizedBox(
                              widthFactor: 0.45,
                              child: ShimmerBlock(height: 9),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: kHomePinGap),
              ],
            ],
          );
        },
      ),
    ),
  );
}
