import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../features/bento/estk_matrix.dart';
import '../features/cards/flip_sim_card.dart';
import '../features/globe/atlas_globe.dart';
import '../features/globe/globe_controller.dart';
import '../features/globe/topojson.dart';
import '../features/hud/hud_stage.dart';
import '../features/hud/hud_theme.dart';
import '../features/settings/theme_mode.dart';
import '../models/sim_card.dart';
import '../services/estk_slots.dart';
import '../services/file_export.dart';
import '../services/ics_export.dart';
import '../services/sim_repository.dart';
import 'backup_page.dart';
import 'sim_form_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.repository, this.atlasLoader});

  final SimRepository? repository;
  final Future<List<GeoCountry>> Function()? atlasLoader;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final SimRepository _repo = widget.repository ?? SimRepository();
  final _globe = GlobeController();
  final _search = TextEditingController();
  final _mobileScroll = ScrollController();
  final _sectionKeys = List.generate(3, (_) => GlobalKey());
  int _section = 0;

  List<SimCard> _cards = [];
  List<SimCard> _archive = [];
  bool _archiveOpen = false;
  bool _loading = true;
  List<GeoCountry>? _countries;
  String? _atlasError;
  MediaType? _mediaFilter;
  String? _country;
  int? _slot;

  @override
  void initState() {
    super.initState();
    _repo.load().then((cards) async {
      final archive = await _repo.loadArchive();
      if (!mounted) return;
      final ids = {for (final c in cards) c.id};
      setState(() {
        _cards = cards;
        // A card in both lists (interrupted archive write) stays in the vault.
        _archive = archive.where((a) => !ids.contains(a.id)).toList();
        _loading = false;
      });
      final errors = _repo.lastLoadErrors;
      if (errors.isNotEmpty) {
        _toast('已拦截 ${errors.length} 张非法卡片（${errors.first}），'
            '原始记录已隔离保存，未写入卡库');
      }
    });
    (widget.atlasLoader ?? loadWorldAtlas)().then(
      (c) => mounted ? setState(() => _countries = c) : null,
      onError: (Object e) =>
          mounted ? setState(() => _atlasError = '地理数据加载失败: $e') : null,
    );
  }

  @override
  void dispose() {
    _globe.dispose();
    _search.dispose();
    _mobileScroll.dispose();
    super.dispose();
  }

  EstkSlotLayout get _layout => layoutEstkSlots(_cards);

  List<SimCard> get _filtered {
    final q = _search.text.trim().toLowerCase();
    final slotCard = _slot == null ? null : _layout.slots[_slot];
    return _cards.where((c) {
      if (_mediaFilter != null && c.mediaType != _mediaFilter) return false;
      if (_country != null && c.countryCode != _country) return false;
      if (slotCard != null && slotCard.id != c.id) return false;
      if (q.isEmpty) return true;
      return [
        c.carrierName,
        c.phoneNumber,
        c.planName,
        c.hostName,
        ...c.boundServices
      ].any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _writes = Future.value();

  /// Applies [change] to the latest cards, writes the result and only then
  /// shows it. Writes run one at a time so overlapping actions never save
  /// stale snapshots. False when the write failed (UI and vault unchanged).
  Future<bool> _persist(List<SimCard> Function(List<SimCard>) change) =>
      _persistBoth((cards, archive) => (change(cards), archive));

  /// Vault + archive variant of [_persist]. The list gaining the card is
  /// written first ([vaultFirst] when it moves into the vault), so an
  /// interrupted move leaves the card in both lists (load keeps the vault
  /// copy) rather than in neither.
  Future<bool> _persistBoth(
      (List<SimCard>, List<SimCard>) Function(List<SimCard>, List<SimCard>)
          change,
      {bool vaultFirst = false}) {
    final result = _writes.then((_) async {
      final (cards, archive) = change(_cards, _archive);
      try {
        if (vaultFirst && !identical(cards, _cards)) await _repo.save(cards);
        if (!identical(archive, _archive)) await _repo.saveArchive(archive);
        if (!vaultFirst && !identical(cards, _cards)) await _repo.save(cards);
      } on Object catch (e) {
        if (mounted) _toast('保存失败，本地数据未改动: $e');
        return false;
      }
      if (mounted) {
        setState(() {
          _cards = cards;
          _archive = archive;
        });
      }
      return true;
    });
    _writes = result;
    return result;
  }

  void _toast(String msg, {VoidCallback? undo}) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: undo == null
          ? const Duration(milliseconds: 4000)
          : const Duration(seconds: 5),
      persist: false,
      action: undo == null
          ? null
          : SnackBarAction(
              key: const Key('undo-checkin'), label: '撤销', onPressed: undo),
    ));

  void _selectCountry(String? code) {
    setState(() => _country = code);
    if (code == null) return;
    final pos = focusFor(code, _countries ?? const []);
    if (pos != null) _globe.flyTo(pos.$1, pos.$2);
  }

  void _onGlobeCountry(String? iso2, String name, double lon, double lat) {
    final known = iso2 != null && _cards.any((c) => c.countryCode == iso2);
    if (known) {
      _selectCountry(iso2);
    } else {
      _globe.flyTo(lon, lat);
      _toast('${iso2 ?? ''} $name · 暂无卡片'.trim());
    }
  }

  Future<void> _checkIn(SimCard card) async {
    SimCard? before, after;
    if (!await _persist((cards) => [
          for (final c in cards)
            if (c.id == card.id) after = (before = c).checkIn() else c
        ])) {
      return;
    }
    if (before == null || after == null) return;
    final (from, to) = (before!, after!);
    _toast(
        '${card.carrierName} 保号打卡成功，死线顺延至 '
        '${DateFormat('yyyy-MM-dd').format(to.nextDeadlineDate)}'
        '（${to.renewalBasis.label}）',
        undo: () => _undoCheckIn(from, to));
  }

  /// Puts back the card as it was before [after]'s check-in, unless it has
  /// changed since.
  Future<void> _undoCheckIn(SimCard before, SimCard after) async {
    final undone = _cards.any((c) => identical(c, after));
    if (undone) {
      await _persist(
          (cards) => [for (final c in cards) identical(c, after) ? before : c]);
    }
    if (mounted) _toast(undone ? '已撤销打卡' : '卡片已变更，无法撤销');
  }

  Future<void> _openForm({SimCard? initial, int? presetSlot}) async {
    final result = await Navigator.of(context).push<SimCard>(MaterialPageRoute(
      builder: (_) => SimFormPage(
          initial: initial, presetSlot: presetSlot, existing: _cards),
    ));
    if (result == null) return;
    final exists = _cards.any((c) => c.id == result.id);
    final today = dateOnly(DateTime.now());
    if (!await _persist((cards) {
      final old = cards.where((c) => c.id == result.id).firstOrNull;
      if (old == null) {
        return [
          ...cards,
          result.withEvent(CardEvent(
              at: today,
              type: CardEventType.create,
              deadline: result.nextDeadlineDate))
        ];
      }
      final changed = describeEdit(old, result);
      final edited = changed.isEmpty
          ? result
          : result.withEvent(CardEvent(
              at: today,
              type: CardEventType.edit,
              deadline: result.nextDeadlineDate,
              note: '修改 ${changed.join('、')}'));
      return [for (final c in cards) c.id == result.id ? edited : c];
    })) {
      return;
    }
    _toast(exists ? '已保存 ${result.carrierName}' : '已新增 ${result.carrierName}');
  }

  /// Moves [card] to the archive: hidden from globe, radar, matrix and stats,
  /// its passport kept. Permanent deletion lives in the archive.
  Future<void> _delete(SimCard card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('归档 SIM 卡'),
        content: Text('「${card.carrierName}」将移入归档区：从地球、雷达、15 槽矩阵和统计中隐藏，'
            '护照历史保留，可随时恢复或在归档区彻底删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              key: const Key('confirm-delete'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('归档')),
        ],
      ),
    );
    if (ok != true) return;
    final today = dateOnly(DateTime.now());
    if (!await _persistBoth((cards, archive) {
      final current = cards.where((c) => c.id == card.id).firstOrNull;
      if (current == null) return (cards, archive);
      return (
        cards.where((c) => c.id != card.id).toList(),
        [
          current
              .copyWith(archivedAt: () => today)
              .withEvent(CardEvent(at: today, type: CardEventType.archive)),
          ...archive
        ]
      );
    })) {
      return;
    }
    if (_slot != null && !_layout.slots.containsKey(_slot)) {
      setState(() => _slot = null);
    }
    _toast('已归档 ${card.carrierName}');
  }

  Future<void> _restore(SimCard card) async {
    final today = dateOnly(DateTime.now());
    var slotCleared = false, restoredNow = false;
    if (!await _persistBoth((cards, archive) {
      // A second tap while the first restore is still saving: nothing to do.
      if (!archive.any((c) => c.id == card.id) ||
          cards.any((c) => c.id == card.id)) {
        return (cards, archive);
      }
      restoredNow = true;
      var restored = card
          .copyWith(archivedAt: () => null)
          .withEvent(CardEvent(at: today, type: CardEventType.restore));
      final n = card.estkSlotNumber;
      if (card.onProgrammableMedium &&
          n != null &&
          cards.any((c) => c.onProgrammableMedium && c.estkSlotNumber == n)) {
        slotCleared = true;
        restored = restored.copyWith(estkSlotNumber: () => null);
      }
      return (
        [...cards, restored],
        archive.where((c) => c.id != card.id).toList()
      );
    }, vaultFirst: true)) {
      return;
    }
    if (!restoredNow) return;
    _toast(slotCleared
        ? '已恢复 ${card.carrierName}；原 eSTK 槽位 #${card.estkSlotNumber} 已被占用，请重新分配'
        : '已恢复 ${card.carrierName}');
  }

  Future<void> _purge(SimCard card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除'),
        content: Text('「${card.carrierName}」及其护照历史将被永久删除，无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              key: const Key('confirm-purge'),
              style: FilledButton.styleFrom(backgroundColor: context.hud.rose),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('彻底删除')),
        ],
      ),
    );
    if (ok != true) return;
    if (!await _persistBoth((cards, archive) =>
        (cards, archive.where((c) => c.id != card.id).toList()))) {
      return;
    }
    _toast('已彻底删除 ${card.carrierName}');
  }

  Future<void> _exportIcs(List<SimCard> cards, String name) async {
    final ics = buildIcsCalendar(cards);
    final path = await saveTextFile(name, ics);
    if (path != null) {
      _toast('已导出日历: $path');
    } else {
      await Clipboard.setData(ClipboardData(text: ics));
      _toast('当前平台无文件系统，ICS 文本已复制到剪贴板');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (Hud.isCompact(context)) return _mobileScaffold(filtered);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          children: [
            _header(),
            const SizedBox(height: 18),
            _hud(filtered),
            const SizedBox(height: 18),
            _bento(),
            const SizedBox(height: 18),
            _searchBar(filtered.length),
            const SizedBox(height: 16),
            _gallery(filtered),
            _archiveSection(),
          ],
        ),
      ),
    );
  }

  Widget _hud(List<SimCard> filtered) => HudStage(
        allCards: _cards,
        filteredCards: filtered,
        countries: _countries,
        atlasError: _atlasError,
        controller: _globe,
        mediaFilter: _mediaFilter,
        onMediaFilter: (m) => setState(() => _mediaFilter = m),
        selectedCountry: _country,
        onSelectCountry: _selectCountry,
        onGlobeCountryTap: _onGlobeCountry,
        onCheckIn: _checkIn,
      );

  void _openBackup() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BackupPage(
          cards: [..._cards, ..._archive],
          onImport: (all) async {
            if (!await _persistBoth((_, __) => (
                  all.where((c) => c.archivedAt == null).toList(),
                  all.where((c) => c.archivedAt != null).toList(),
                ))) {
              return false;
            }
            setState(() {
              _country = null;
              _slot = null;
            });
            return true;
          },
        ),
      ));

  // ---------------------------------------------------------------------------
  // Phone portrait presentation: a dedicated layout, not the desktop page
  // scaled down. One scrolling column split into three sections (Atlas /
  // Bento / Cards) with a floating glass dock that jumps between them and
  // hosts the primary "new SIM" action within thumb reach.
  // ---------------------------------------------------------------------------

  static const _sections = [
    (Icons.public, '地球'),
    (Icons.grid_view_rounded, '概览'),
    (Icons.style_outlined, '卡库'),
  ];

  Widget _mobileScaffold(List<SimCard> filtered) {
    final mq = MediaQuery.of(context);
    final keyboardOpen = mq.viewInsets.bottom > 0;
    final dockSpace = 64 + 12 + mq.viewPadding.bottom;
    Widget section(int i, Widget child) =>
        KeyedSubtree(key: _sectionKeys[i], child: child);
    return Scaffold(
      body: Stack(children: [
        SafeArea(
          bottom: false,
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: (_) {
              _syncSection();
              return false;
            },
            child: SingleChildScrollView(
              key: const Key('mobile-scroll'),
              controller: _mobileScroll,
              padding: EdgeInsets.fromLTRB(
                  12, 8, 12, keyboardOpen ? 16 : dockSpace + 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  section(
                      0,
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _mobileHeader(),
                            const SizedBox(height: 10),
                            _hud(filtered),
                          ])),
                  const SizedBox(height: 22),
                  section(
                      1,
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle('Bento · 概览', '${_cards.length} 张卡'),
                            _bento(),
                          ])),
                  const SizedBox(height: 22),
                  section(
                      2,
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _sectionTitle('Card Vault · 卡库',
                                '${filtered.length} / ${_cards.length}'),
                            _searchBar(filtered.length),
                            const SizedBox(height: 14),
                            _gallery(filtered),
                            _archiveSection(),
                          ])),
                ],
              ),
            ),
          ),
        ),
        if (!keyboardOpen)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + mq.viewPadding.bottom,
            child: _dock(),
          ),
      ]),
    );
  }

  void _syncSection() {
    var current = 0;
    for (var i = 0; i < _sectionKeys.length; i++) {
      final box = _sectionKeys[i].currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.attached &&
          box.localToGlobal(Offset.zero).dy <= 200) {
        current = i;
      }
    }
    if (current != _section) setState(() => _section = current);
  }

  void _jumpTo(int i) {
    final ctx = _sectionKeys[i].currentContext;
    setState(() => _section = i);
    if (i == 0) {
      _mobileScroll.animateTo(0,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic);
    } else if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic);
    }
  }

  Widget _sectionTitle(String title, String meta) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Row(children: [
          Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                  color: context.hud.sky,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(child: HudLabel(title, color: context.hud.fg)),
          Text(meta,
              style: Hud.mono.copyWith(fontSize: 11, color: context.hud.dim)),
        ]),
      );

  Widget _mobileHeader() => Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: context.hud.sky.withValues(alpha: .5)),
            color: context.hud.sky.withValues(alpha: .12),
          ),
          child: Icon(Icons.public, color: context.hud.sky, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Flexible(
                child: Text('SIMVault',
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color: context.hud.sky.withValues(alpha: .5))),
                child: Text('v3.2',
                    style: Hud.mono
                        .copyWith(fontSize: 9.5, color: context.hud.sky)),
              ),
            ]),
            Text('WORLD CARD ATLAS · LOCAL-FIRST',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Hud.mono.copyWith(
                    fontSize: 9.5, letterSpacing: 1, color: context.hud.dim)),
          ]),
        ),
        IconButton(
          key: const Key('theme-menu'),
          tooltip: '主题：浅色 / 深色 / 跟随系统',
          onPressed: () => showThemeModeSheet(context),
          icon: Icon(
              themeModeOptions
                  .firstWhere((o) => o.$1 == ThemeModeScope.of(context).value)
                  .$2,
              color: context.hud.muted),
        ),
        IconButton(
          key: const Key('export-all-ics'),
          tooltip: '导出全部 ICS',
          onPressed: () => _exportIcs(_cards, 'SIMVault_all_deadlines.ics'),
          icon: Icon(Icons.event_outlined, color: context.hud.muted),
        ),
        IconButton(
          key: const Key('open-backup'),
          tooltip: 'JSON 备份',
          onPressed: _openBackup,
          icon: Icon(Icons.data_object, color: context.hud.muted),
        ),
      ]);

  Widget _dock() => GlassPanel(
        key: const Key('mobile-dock'),
        radius: 22,
        padding: const EdgeInsets.all(6),
        tint: context.hud.dockTint,
        child: SizedBox(
          height: 52,
          child: Row(children: [
            for (var i = 0; i < _sections.length; i++)
              Expanded(
                child: InkWell(
                  key: Key('dock-$i'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _jumpTo(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: _section == i
                          ? context.hud.sky.withValues(alpha: .14)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: _section == i
                              ? context.hud.sky.withValues(alpha: .35)
                              : Colors.transparent),
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_sections[i].$1,
                              size: 20,
                              color: _section == i
                                  ? context.hud.sky
                                  : context.hud.muted),
                          const SizedBox(height: 2),
                          Text(_sections[i].$2,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _section == i
                                      ? context.hud.sky
                                      : context.hud.muted)),
                        ]),
                  ),
                ),
              ),
            const SizedBox(width: 6),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const Key('add-card'),
                style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16))),
                onPressed: () => _openForm(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增'),
              ),
            ),
          ]),
        ),
      );

  Widget _header() => Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: context.hud.sky.withValues(alpha: .5)),
                color: context.hud.sky.withValues(alpha: .12),
              ),
              child: Icon(Icons.public, color: context.hud.sky),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('SIMVault',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: context.hud.sky.withValues(alpha: .5))),
                  child: Text('v3.2 WORLD CARD ATLAS',
                      style: Hud.mono
                          .copyWith(fontSize: 10, color: context.hud.sky)),
                ),
              ]),
              Text('GLOBAL SIM ATLAS · KEEP-ALIVE RADAR · LOCAL-FIRST',
                  style:
                      Hud.mono.copyWith(fontSize: 10, color: context.hud.dim)),
            ]),
          ]),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const ThemeModeSwitch(),
                OutlinedButton.icon(
                  key: const Key('export-all-ics'),
                  onPressed: () =>
                      _exportIcs(_cards, 'SIMVault_all_deadlines.ics'),
                  icon: const Icon(Icons.event, size: 16),
                  label: const Text('导出全部 ICS'),
                ),
                OutlinedButton.icon(
                  key: const Key('open-backup'),
                  onPressed: _openBackup,
                  icon: const Icon(Icons.data_object, size: 16),
                  label: const Text('JSON 备份'),
                ),
                FilledButton.icon(
                  key: const Key('add-card'),
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新增 SIM'),
                ),
              ]),
        ],
      );

  Widget _bento() {
    final layout = _layout;
    final sorted = [..._cards]
      ..sort((a, b) => a.nextDeadlineDate.compareTo(b.nextDeadlineDate));
    final urgent = sorted.isEmpty ? null : sorted.first;
    final monthly = _cards.fold<double>(0, (s, c) => s + c.monthlyCny);
    final annual = annualCostByCurrency(_cards);
    final annualCny = _cards.fold<double>(0, (s, c) => s + c.annualCny);
    int count(MediaType m) => _cards.where((c) => c.mediaType == m).length;
    int tier(UrgencyTier t) => _cards.where((c) => c.urgency() == t).length;
    final regions = {for (final c in _cards) c.countryCode}.length;
    final active = _cards.where((c) => c.isActive).length;

    final tiles = <Widget>[
      _BentoTile(children: [
        const HudLabel('01 / Global Vault'),
        const SizedBox(height: 10),
        Text('${_cards.length}',
            style:
                Hud.mono.copyWith(fontSize: 34, fontWeight: FontWeight.w900)),
        Text('$regions 个国家/地区 · $active 张在线 / ${_cards.length - active} 张待机',
            style: TextStyle(fontSize: 11, color: context.hud.muted)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(children: [
            for (final m in MediaType.values)
              if (count(m) > 0)
                Expanded(
                    flex: count(m),
                    child:
                        Container(height: 6, color: context.hud.mediaColor(m))),
            if (_cards.isEmpty)
              Expanded(child: Container(height: 6, color: context.hud.line)),
          ]),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 10, children: [
          for (final m in MediaType.values)
            Text('● ${m.label} ${count(m)}',
                style: TextStyle(
                    fontSize: 10.5, color: context.hud.mediaColor(m))),
        ]),
      ]),
      _BentoTile(children: [
        HudLabel('02 / Deadline Shield', color: context.hud.rose),
        const SizedBox(height: 10),
        if (urgent == null)
          Text('暂无卡片', style: TextStyle(color: context.hud.dim))
        else ...[
          Row(children: [
            Expanded(
              child: Text(urgent.carrierName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            Text('${urgent.daysRemaining()}d',
                style: Hud.mono.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: context.hud.tierColor(urgent.urgency()))),
          ]),
          Text(urgent.keepAliveAction,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: context.hud.muted)),
          const SizedBox(height: 10),
          Row(children: [
            Text(
                'P1 ${tier(UrgencyTier.p1)} · P2 ${tier(UrgencyTier.p2)} · OK ${tier(UrgencyTier.ok)}',
                style:
                    Hud.mono.copyWith(fontSize: 11, color: context.hud.muted)),
            const Spacer(),
            TextButton(
              key: const Key('bento-checkin'),
              onPressed: () => _checkIn(urgent),
              child: const Text('立即打卡'),
            ),
          ]),
        ],
      ]),
      _BentoTile(children: [
        HudLabel(
            Hud.isCompact(context)
                ? '03 / Cost · CNY'
                : '03 / Cost Engine (CNY)',
            color: context.hud.emerald),
        const SizedBox(height: 10),
        Text('¥${monthly.toStringAsFixed(2)}',
            style:
                Hud.mono.copyWith(fontSize: 30, fontWeight: FontWeight.w900)),
        Text('/ 月 · 年化 ¥${(monthly * 12).toStringAsFixed(2)}',
            style: TextStyle(fontSize: 11, color: context.hud.muted)),
        const SizedBox(height: 12),
        Text(
            exchangeRatesToCny.entries
                .where((e) =>
                    e.key != 'CNY' && _cards.any((c) => c.currency == e.key))
                .map((e) => '${e.key} ${e.value}')
                .join('  '),
            style: Hud.mono.copyWith(fontSize: 10.5, color: context.hud.dim)),
        const SizedBox(height: 8),
        Text('年保号成本 ≈ ¥${annualCny.toStringAsFixed(0)}',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: context.hud.emerald)),
        Text(
            annual.isEmpty
                ? '—'
                : annual.entries
                    .map((e) => '${e.key} ${_money(e.value)}')
                    .join(' · '),
            key: const Key('annual-cost'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Hud.mono.copyWith(fontSize: 10.5, color: context.hud.muted)),
      ]),
      _BentoTile(
        key: const Key('estk-bento'),
        children: [
          EstkMatrixCard(
            compact: Hud.isCompact(context),
            layout: layout,
            selectedSlot: _slot,
            onSelectSlot: (n) => setState(() => _slot = n),
            onWriteToSlot: (n) => _openForm(presetSlot: n),
          ),
        ],
      ),
    ];

    if (Hud.isCompact(context)) {
      // Phone bento: two small stat tiles side by side, the deadline and the
      // 15-slot matrix full width, every tile sized by its own content.
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: tiles[0]),
            const SizedBox(width: 10),
            Expanded(child: tiles[2]),
          ]),
        ),
        const SizedBox(height: 10),
        tiles[1],
        const SizedBox(height: 10),
        tiles[3],
      ]);
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1200 ? 4 : (c.maxWidth >= 640 ? 2 : 1);
      final w = (c.maxWidth - 14 * (cols - 1)) / cols;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final t in tiles) SizedBox(width: w, height: 232, child: t)
        ],
      );
    });
  }

  Widget _searchBar(int shown) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: context.hud.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.hud.line),
        ),
        child: Row(children: [
          Icon(Icons.search, size: 18, color: context.hud.dim),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: '搜索运营商 / 号码 / 宿主 / 绑定服务…',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          Text('$shown / ${_cards.length}',
              style: Hud.mono.copyWith(fontSize: 11, color: context.hud.muted)),
          if (_mediaFilter != null ||
              _country != null ||
              _slot != null ||
              _search.text.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                _mediaFilter = null;
                _country = null;
                _slot = null;
                _search.clear();
              }),
              child: const Text('重置筛选'),
            ),
        ]),
      );

  Widget _archiveSection() {
    if (_archive.isEmpty) return const SizedBox.shrink();
    final h = context.hud;
    Widget row(SimCard c) => Padding(
          key: Key('archived-${c.id}'),
          padding: const EdgeInsets.only(bottom: 8),
          child: GlassPanel(
            radius: 14,
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(children: [
              Expanded(
                child: ColorFiltered(
                  colorFilter: _greyscale,
                  child: Opacity(
                    opacity: .7,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${c.countryCode}  ${c.carrierName}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                          Text(
                              '${c.phoneNumber.isEmpty ? '未录入号码' : c.phoneNumber} · '
                              '归档于 ${c.archivedAt == null ? '—' : DateFormat('yyyy-MM-dd').format(c.archivedAt!)} · '
                              '护照 ${c.events.length} 条',
                              overflow: TextOverflow.ellipsis,
                              style: Hud.mono
                                  .copyWith(fontSize: 10.5, color: h.muted)),
                        ]),
                  ),
                ),
              ),
              TextButton(
                  key: Key('restore-${c.id}'),
                  onPressed: () => _restore(c),
                  child: const Text('恢复')),
              TextButton(
                  key: Key('purge-${c.id}'),
                  style: TextButton.styleFrom(foregroundColor: h.rose),
                  onPressed: () => _purge(c),
                  child: const Text('彻底删除')),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: const Key('archive-toggle'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _archiveOpen = !_archiveOpen),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Hud.minTap),
            child: Row(children: [
              Icon(Icons.inventory_2_outlined, size: 18, color: h.dim),
              const SizedBox(width: 8),
              Expanded(
                  child: HudLabel('Archive · 归档区 ${_archive.length}',
                      color: h.muted)),
              Icon(_archiveOpen ? Icons.expand_less : Icons.expand_more,
                  color: h.dim),
            ]),
          ),
        ),
        if (_archiveOpen) ...[
          const SizedBox(height: 8),
          for (final c in _archive) row(c),
        ],
      ]),
    );
  }

  Widget _gallery(List<SimCard> cards) {
    if (cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          Icon(Icons.sim_card_outlined, size: 48, color: context.hud.dim),
          const SizedBox(height: 8),
          Text(_cards.isEmpty ? '金库为空，点击「新增 SIM」或从 JSON 备份导入' : '当前筛选无卡片',
              style: TextStyle(color: context.hud.muted)),
        ]),
      );
    }
    return LayoutBuilder(builder: (context, c) {
      final cols = math.max(1, ((c.maxWidth + 16) / (380 + 16)).floor());
      final w = (c.maxWidth - 16 * (cols - 1)) / cols;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final card in cards)
            SizedBox(
              width: w,
              child: FlipSimCard(
                key: ValueKey('flip-card-${card.id}'),
                card: card,
                highlighted: _slot != null,
                onCheckIn: () => _checkIn(card),
                onEdit: () => _openForm(initial: card),
                onDelete: () => _delete(card),
                onExportIcs: () => _exportIcs([
                  card
                ], 'SIMVault_${card.carrierName}_${card.nextDeadlineDate.toIso8601String().substring(0, 10)}.ics'),
              ),
            ),
        ],
      );
    });
  }
}

String _money(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

/// Field names that differ between two versions of a card, for the passport.
List<String> describeEdit(SimCard a, SimCard b) => [
      if (a.carrierName != b.carrierName) '运营商',
      if (a.phoneNumber != b.phoneNumber) '号码',
      if (a.nextDeadlineDate != b.nextDeadlineDate) '死线',
      if (a.keepAliveCycleDays != b.keepAliveCycleDays) '周期',
      if (a.keepAliveType != b.keepAliveType) '保号类型',
      if (a.renewalBasis != b.renewalBasis) '续期算法',
      if (a.cycleCost != b.cycleCost ||
          a.currency != b.currency ||
          a.billingCycle != b.billingCycle)
        '资费',
      if (a.balance != b.balance) '余额',
      if (a.estkSlotNumber != b.estkSlotNumber ||
          a.hostName != b.hostName ||
          a.slotDetail != b.slotDetail ||
          a.locationType != b.locationType)
        '存放位置',
      if (a.iccid != b.iccid ||
          a.pin1 != b.pin1 ||
          a.puk1 != b.puk1 ||
          a.esimLpaCode != b.esimLpaCode)
        '卡背机密',
    ];

const _greyscale = ColorFilter.matrix([
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

class _BentoTile extends StatelessWidget {
  const _BentoTile({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => CustomPaint(
      foregroundPainter:
          GlassRimPainter(radius: 18, color: context.hud.glassRim),
      child: Container(
        padding: EdgeInsets.all(Hud.isCompact(context) ? 14 : 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: context.hud.tileGradient,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.hud.line),
          boxShadow: context.hud.glassShadow,
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ));
}
