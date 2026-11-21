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
    this.onRenameSlot,
    this.compact = false,
  });

  final EstkSlotLayout layout;
  final int? selectedSlot;
  final ValueChanged<int?> onSelectSlot;
  final ValueChanged<int> onWriteToSlot;

  /// Long-press / right-click: edit the slot's profile nickname.
  final ValueChanged<int>? onRenameSlot;
  final bool compact;

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
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.hud.amber)),
      ]),
      const SizedBox(height: 10),
      for (var row = 0; row < estkRows; row++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            for (var col = 0; col < estkColumns; col++) ...[
              if (col > 0) const SizedBox(width: 6),
              Expanded(child: _slot(context, row * estkColumns + col + 1)),
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
                    color: layout.overflow.isEmpty
                        ? context.hud.dim
                        : context.hud.rose))
            : selectedCard != null
                ? Text(
                    '槽位 #$selected 已占用 · '
                    '${selectedCard.profileName.isEmpty ? '' : '「${selectedCard.profileName}」'}'
                    '${selectedCard.carrierName} '
                    '${selectedCard.phoneNumber} · ${selectedCard.hostName} ${selectedCard.slotDetail}',
                    key: const Key('slot-detail'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: context.hud.amber))
                : Row(key: const Key('slot-detail'), children: [
                    Expanded(
                      child: Text('槽位 #$selected 空闲可用',
                          style: TextStyle(
                              fontSize: 11, color: context.hud.muted)),
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

  Widget _slot(BuildContext context, int n) {
    final h = context.hud;
    final card = layout.slots[n];
    final isSelected = selectedSlot == n;
    final occupied = card != null;
    return Tooltip(
      message: occupied
          ? '槽位 #$n${card.profileName.isEmpty ? '' : '「${card.profileName}」'}: '
              '${card.carrierName} (${card.phoneNumber}) · 长按/右键改昵称'
          : '槽位 #$n: 空闲可用',
      child: InkWell(
        key: Key('slot-$n'),
        borderRadius: BorderRadius.circular(7),
        onTap: () => onSelectSlot(isSelected ? null : n),
        onLongPress: onRenameSlot == null ? null : () => onRenameSlot!(n),
        onSecondaryTap: onRenameSlot == null ? null : () => onRenameSlot!(n),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: compact ? Hud.minTap : 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: occupied
                ? (isSelected
                    ? context.hud.amber
                    : context.hud.blue.withValues(alpha: .35))
                : h.well,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
                color: isSelected
                    ? h.fg
                    : occupied
                        ? h.sky.withValues(alpha: .6)
                        : h.wellEdge),
          ),
          child: Text(
            occupied
                ? '#$n ${card.profileName.isEmpty ? card.countryCode : card.profileName}'
                : '#$n',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Hud.mono.copyWith(
                fontSize: 10,
                fontWeight: occupied ? FontWeight.w800 : FontWeight.w400,
                color: occupied
                    ? (isSelected ? h.onAccent : h.fg)
                    : context.hud.dim),
          ),
        ),
      ),
    );
  }
}
