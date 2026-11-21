import 'package:flutter/material.dart';

import '../../models/medium.dart';
import '../../services/estk_slots.dart';
import '../hud/hud_theme.dart';

/// Medium matrix: one tab per medium (eSTK, 9eSIM, built-in eSIM…), each
/// rendering its own capacity as 5-column slots driven by the card list.
class EstkMatrixCard extends StatelessWidget {
  const EstkMatrixCard({
    super.key,
    required this.layout,
    required this.selectedSlot,
    required this.onSelectSlot,
    required this.onWriteToSlot,
    this.onRenameSlot,
    this.compact = false,
    this.media = const [legacyEstkMedium],
    this.onSelectMedium,
    this.onManageMedia,
  });

  final List<Medium> media;
  final ValueChanged<String>? onSelectMedium;
  final VoidCallback? onManageMedia;

  /// Above this many rows the grid scrolls inside the tile (the desktop
  /// bento tile has a fixed height, so it keeps the old 3 rows visible).
  int get visibleRows => compact
      ? 4
      : media.length > 1
          ? estkRows - 1
          : estkRows;

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
        Expanded(
            child: HudLabel('04 / 载体矩阵 · ${layout.medium.name}',
                key: const Key('medium-title'))),
        Text(layout.usageLabel,
            key: const Key('slot-usage'),
            style: Hud.mono.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.hud.amber)),
        if (onManageMedia != null)
          SizedBox(
            width: 28,
            height: 20,
            child: IconButton(
              key: const Key('manage-media'),
              tooltip: '管理载体（新增 / 编辑 / 删除）',
              padding: EdgeInsets.zero,
              iconSize: 16,
              onPressed: onManageMedia,
              icon: Icon(Icons.tune, color: context.hud.muted),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      if (media.length > 1) ...[
        _tabs(context),
        const SizedBox(height: 6),
      ],
      _grid(context),
      const SizedBox(height: 4),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: selected == null
            ? Text(
                layout.overflow.isEmpty
                    ? '点击槽位查看占用；空槽可直接写入新 Profile'
                    : '⚠ ${layout.overflow.length} 张卡超出 ${layout.capacity} 槽',
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

  Widget _tabs(BuildContext context) => SizedBox(
        height: 32,
        child: Row(children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final m in media)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      key: Key('medium-tab-${m.id}'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      labelStyle: const TextStyle(fontSize: 11),
                      label: Text('${m.name} · ${m.capacity}'),
                      selected: m.id == layout.medium.id,
                      onSelected: onSelectMedium == null
                          ? null
                          : (_) => onSelectMedium!(m.id),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      );

  Widget _grid(BuildContext context) {
    final rowHeight = (compact ? Hud.minTap : 30) + 6.0;
    final rows = Column(children: [
      for (var row = 0; row < layout.rows; row++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            for (var col = 0; col < estkColumns; col++) ...[
              if (col > 0) const SizedBox(width: 6),
              Expanded(
                  child: row * estkColumns + col + 1 <= layout.capacity
                      ? _slot(context, row * estkColumns + col + 1)
                      : const SizedBox.shrink()),
            ],
          ]),
        ),
    ]);
    if (layout.rows <= visibleRows) return rows;
    return SizedBox(
      key: const Key('medium-grid-scroll'),
      height: rowHeight * visibleRows,
      child: Scrollbar(child: SingleChildScrollView(child: rows)),
    );
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
