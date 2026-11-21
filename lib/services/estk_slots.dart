import '../models/medium.dart';
import '../models/sim_card.dart';

const estkSlotCount = 15;
const estkColumns = 5;
const estkRows = 3;

class EstkSlotLayout {
  const EstkSlotLayout(this.slots, this.overflow,
      {this.medium = legacyEstkMedium});

  /// Slot number (1..capacity) → card occupying it.
  final Map<int, SimCard> slots;

  /// Cards assigned to the medium that did not fit in its slots.
  final List<SimCard> overflow;
  final Medium medium;

  int get capacity => medium.capacity;
  int get rows => (capacity + estkColumns - 1) ~/ estkColumns;
  int get occupied => slots.length;
  int get free => capacity - occupied;
  String get usageLabel => '占用 $occupied / $capacity 槽位';
}

/// The legacy 15-slot eSTK matrix (pre-v3.4 behaviour).
EstkSlotLayout layoutEstkSlots(List<SimCard> cards) =>
    layoutMediumSlots(legacyEstkMedium, cards);

/// Places every card on [medium] into its slots. Explicit valid slot
/// numbers win; the rest take the lowest free slot.
EstkSlotLayout layoutMediumSlots(Medium medium, List<SimCard> cards) {
  final on = cards.where((c) => c.resolvedMediumId == medium.id).toList();
  final slots = <int, SimCard>{};
  final pending = <SimCard>[];
  for (final card in on) {
    final n = card.estkSlotNumber;
    if (n != null && n >= 1 && n <= medium.capacity && !slots.containsKey(n)) {
      slots[n] = card;
    } else {
      pending.add(card);
    }
  }
  final overflow = <SimCard>[];
  for (final card in pending) {
    final freeSlot = List.generate(medium.capacity, (i) => i + 1)
        .where((n) => !slots.containsKey(n))
        .firstOrNull;
    if (freeSlot == null) {
      overflow.add(card);
    } else {
      slots[freeSlot] = card;
    }
  }
  return EstkSlotLayout(slots, overflow, medium: medium);
}

/// [media] plus a placeholder for every medium id a card points at but the
/// list lacks (e.g. a backup restored without its medium list), so no card
/// silently drops out of the matrix.
List<Medium> reconcileMedia(List<Medium> media, Iterable<SimCard> cards) {
  final out = [...media];
  for (final c in cards) {
    final id = c.resolvedMediumId;
    if (id == null || out.any((m) => m.id == id)) continue;
    out.add(id == legacyMediumId
        ? legacyEstkMedium
        : Medium(id: id, name: '未知载体', kind: MediumKind.euicc, capacity: 15));
  }
  return out;
}
