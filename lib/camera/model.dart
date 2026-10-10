class CameraModel {
  const CameraModel(this.name, this.slotCount, {this.experimental = false});
  final String name;
  final int slotCount;
  final bool experimental;

  static const x100vi = CameraModel('X100VI', 7);
  static const xm5 = CameraModel('X-M5', 4, experimental: true);
  static const xt5 = CameraModel('X-T5', 7, experimental: true);
  static const supported = [x100vi, xm5, xt5];

  static CameraModel? fromName(String name) {
    for (final model in supported) {
      if (model.name == name.trim().toUpperCase()) return model;
    }
    return null;
  }

  String get slotLabel => 'C1–C$slotCount';
  Set<int> get slots => {for (var i = 1; i <= slotCount; i++) i};
  void validateSlots(Iterable<int> slots) {
    for (final slot in slots) {
      if (slot < 1 || slot > slotCount) {
        throw RangeError.range(slot, 1, slotCount, 'slot');
      }
    }
  }
}
