/// Hardware power is optional; the UI also paints black while blanked.
abstract class DisplayPower {
  Future<bool> get available;
  Future<bool> setBlanked(bool blanked);
}

class NoDisplayPower implements DisplayPower {
  const NoDisplayPower();

  @override
  Future<bool> get available async => false;

  @override
  Future<bool> setBlanked(bool blanked) async => false;
}
