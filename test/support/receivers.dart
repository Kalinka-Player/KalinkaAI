import 'package:kalinka/providers/receiver_provider.dart';

/// Unrelated screen fixtures represent a server with no receiver plugins.
/// Keep their inventory local, as their other server responses already are.
final noReceivers = receiversProvider.overrideWith(_NoReceivers.new);

class _NoReceivers extends ReceiversNotifier {
  @override
  ReceiverInventory build() => const ReceiverInventory();
}
