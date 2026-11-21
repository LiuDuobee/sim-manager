import '../models/sim_card.dart';

const estkSlotCount = 15;
const estkColumns = 5;
const estkRows = 3;

class EstkSlotLayout {
  const EstkSlotLayout(this.slots, this.overflow);

  /// Slot number (1..15) → card occupying it.
  final Map<int, SimCard> slots;

  /// Programmable-medium cards that did not fit in 15 slots.
  final List<SimCard> overflow;

  int get occupied => slots.length;
  int get free => estkSlotCount - occupied;
  String get usageLabel => '占用 $occupied / $estkSlotCount 槽位';
}

/// Places every card hosted on a programmable eSTK/5ber medium into the
/// 15-slot matrix. Explicit valid `estkSlotNumber`s win; the rest take the
/// lowest free slot.
EstkSlotLayout layoutEstkSlots(List<SimCard> cards) {
  final programmable = cards.where((c) => c.onProgrammableMedium).toList();
  final slots = <int, SimCard>{};
  final pending = <SimCard>[];
  for (final card in programmable) {
    final n = card.estkSlotNumber;
    if (n != null && n >= 1 && n <= estkSlotCount && !slots.containsKey(n)) {
      slots[n] = card;
    } else {
      pending.add(card);
    }
  }
  final overflow = <SimCard>[];
  for (final card in pending) {
    final freeSlot = List.generate(estkSlotCount, (i) => i + 1)
        .where((n) => !slots.containsKey(n))
        .firstOrNull;
    if (freeSlot == null) {
      overflow.add(card);
    } else {
      slots[freeSlot] = card;
    }
  }
  return EstkSlotLayout(slots, overflow);
}
