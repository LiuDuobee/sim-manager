import 'package:flutter/material.dart';

import '../../services/estk_slots.dart';
import '../hud/hud_theme.dart';

/// 5×3 eSTK.me / 5ber slot matrix driven by the real card list.
class EstkMatrixCard extends StatelessWidget {
  const EstkMatrixCard({
    super.key,
    required this.layout,
    required this.selectedSlot,
    required this.onSelectSlot,
    required this.onWriteToSlot,
  });

  final EstkSlotLayout layout;
  final int? selectedSlot;
  final ValueChanged<int?> onSelectSlot;
  final ValueChanged<int> onWriteToSlot;

  @override
  Widget build(BuildContext context) {
    final selected = selectedSlot;
    final selectedCard = selected == null ? null : layout.slots[selected];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: HudLabel('04 / eSTK.me 15-Slot Matrix')),
        Text(layout.usageLabel,
            key: const Key('slot-usage'),
            style: Hud.mono.copyWith(
                fontSize: 11, fontWeight: FontWeight.w700, color: Hud.amber)),
      ]),
      const SizedBox(height: 10),
      for (var row = 0; row < estkRows; row++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            for (var col = 0; col < estkColumns; col++) ...[
              if (col > 0) const SizedBox(width: 6),
              Expanded(child: _slot(row * estkColumns + col + 1)),
            ],
          ]),
        ),
      const SizedBox(height: 4),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: selected == null
            ? Text(
                layout.overflow.isEmpty
                    ? '点击槽位查看占用；空槽可直接写入新 Profile'
                    : '⚠ ${layout.overflow.length} 张可编程介质卡超出 15 槽',
                key: const ValueKey('hint'),
                style: TextStyle(
                    fontSize: 11,
                    color: layout.overflow.isEmpty ? Hud.dim : Hud.rose))
            : selectedCard != null
                ? Text(
                    '槽位 #$selected 已占用 · ${selectedCard.carrierName} '
                    '${selectedCard.phoneNumber} · ${selectedCard.hostName} ${selectedCard.slotDetail}',
                    key: const Key('slot-detail'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Hud.amber))
                : Row(key: const Key('slot-detail'), children: [
                    Expanded(
                      child: Text('槽位 #$selected 空闲可用',
                          style:
                              const TextStyle(fontSize: 11, color: Hud.muted)),
                    ),
                    TextButton(
                      key: const Key('slot-write'),
                      onPressed: () => onWriteToSlot(selected),
                      child: const Text('写入新 Profile'),
                    ),
                  ]),
      ),
    ]);
  }

  Widget _slot(int n) {
    final card = layout.slots[n];
    final isSelected = selectedSlot == n;
    final occupied = card != null;
    return Tooltip(
      message: occupied
          ? '槽位 #$n: ${card.carrierName} (${card.phoneNumber})'
          : '槽位 #$n: 空闲可用',
      child: InkWell(
        key: Key('slot-$n'),
        borderRadius: BorderRadius.circular(7),
        onTap: () => onSelectSlot(isSelected ? null : n),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: occupied
                ? (isSelected ? Hud.amber : Hud.blue.withValues(alpha: .35))
                : const Color(0x99020617),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
                color: isSelected
                    ? Colors.white
                    : occupied
                        ? Hud.sky.withValues(alpha: .6)
                        : Colors.white.withValues(alpha: .06)),
          ),
          child: Text(
            occupied ? '#$n ${card.countryCode}' : '#$n',
            style: Hud.mono.copyWith(
                fontSize: 10,
                fontWeight: occupied ? FontWeight.w800 : FontWeight.w400,
                color: occupied
                    ? (isSelected ? const Color(0xFF020617) : Colors.white)
                    : Hud.dim),
          ),
        ),
      ),
    );
  }
}
