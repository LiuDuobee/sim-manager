import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/bento/estk_matrix.dart';
import '../features/cards/flip_sim_card.dart';
import '../features/globe/atlas_globe.dart';
import '../features/globe/globe_controller.dart';
import '../features/globe/topojson.dart';
import '../features/hud/hud_stage.dart';
import '../features/hud/hud_theme.dart';
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

  List<SimCard> _cards = [];
  bool _loading = true;
  List<GeoCountry>? _countries;
  String? _atlasError;
  MediaType? _mediaFilter;
  String? _country;
  int? _slot;

  @override
  void initState() {
    super.initState();
    _repo.load().then((cards) {
      if (!mounted) return;
      setState(() {
        _cards = cards;
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
  Future<bool> _persist(List<SimCard> Function(List<SimCard>) change) {
    final result = _writes.then((_) async {
      final cards = change(_cards);
      try {
        await _repo.save(cards);
      } on Object catch (e) {
        if (mounted) _toast('保存失败，本地数据未改动: $e');
        return false;
      }
      if (mounted) setState(() => _cards = cards);
      return true;
    });
    _writes = result;
    return result;
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));

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
    if (!await _persist((cards) =>
        [for (final c in cards) c.id == card.id ? c.checkIn() : c])) {
      return;
    }
    _toast('${card.carrierName} 保号打卡成功，死线顺延 ${card.keepAliveCycleDays} 天');
  }

  Future<void> _openForm({SimCard? initial, int? presetSlot}) async {
    final result = await Navigator.of(context).push<SimCard>(MaterialPageRoute(
      builder: (_) => SimFormPage(
          initial: initial, presetSlot: presetSlot, existing: _cards),
    ));
    if (result == null) return;
    final exists = _cards.any((c) => c.id == result.id);
    if (!await _persist((cards) => cards.any((c) => c.id == result.id)
        ? [for (final c in cards) c.id == result.id ? result : c]
        : [...cards, result])) {
      return;
    }
    _toast(exists ? '已保存 ${result.carrierName}' : '已新增 ${result.carrierName}');
  }

  Future<void> _delete(SimCard card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除 SIM 卡'),
        content: Text('确定删除「${card.carrierName}」？此操作会立即写入本地存储。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              key: const Key('confirm-delete'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    if (!await _persist(
        (cards) => cards.where((c) => c.id != card.id).toList())) {
      return;
    }
    if (_slot != null && !_layout.slots.containsKey(_slot)) {
      setState(() => _slot = null);
    }
    _toast('已删除 ${card.carrierName}');
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
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                children: [
                  _header(),
                  const SizedBox(height: 18),
                  HudStage(
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
                  ),
                  const SizedBox(height: 18),
                  _bento(),
                  const SizedBox(height: 18),
                  _searchBar(filtered.length),
                  const SizedBox(height: 16),
                  _gallery(filtered),
                ],
              ),
            ),
    );
  }

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
                border: Border.all(color: Hud.sky.withValues(alpha: .5)),
                color: Hud.sky.withValues(alpha: .12),
              ),
              child: const Icon(Icons.public, color: Hud.sky),
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
                      border: Border.all(color: Hud.sky.withValues(alpha: .5))),
                  child: Text('v3.2 WORLD CARD ATLAS',
                      style: Hud.mono.copyWith(fontSize: 10, color: Hud.sky)),
                ),
              ]),
              Text('GLOBAL SIM ATLAS · KEEP-ALIVE RADAR · LOCAL-FIRST',
                  style: Hud.mono.copyWith(fontSize: 10, color: Hud.dim)),
            ]),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              key: const Key('export-all-ics'),
              onPressed: () => _exportIcs(_cards, 'SIMVault_all_deadlines.ics'),
              icon: const Icon(Icons.event, size: 16),
              label: const Text('导出全部 ICS'),
            ),
            OutlinedButton.icon(
              key: const Key('open-backup'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BackupPage(
                  cards: _cards,
                  onImport: (cards) async {
                    if (!await _persist((_) => cards)) return false;
                    setState(() {
                      _country = null;
                      _slot = null;
                    });
                    return true;
                  },
                ),
              )),
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
            style: const TextStyle(fontSize: 11, color: Hud.muted)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(children: [
            for (final m in MediaType.values)
              if (count(m) > 0)
                Expanded(
                    flex: count(m),
                    child: Container(height: 6, color: Hud.mediaColor(m))),
            if (_cards.isEmpty)
              Expanded(child: Container(height: 6, color: Hud.line)),
          ]),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 10, children: [
          for (final m in MediaType.values)
            Text('● ${m.label} ${count(m)}',
                style: TextStyle(fontSize: 10.5, color: Hud.mediaColor(m))),
        ]),
      ]),
      _BentoTile(children: [
        const HudLabel('02 / Deadline Shield', color: Hud.rose),
        const SizedBox(height: 10),
        if (urgent == null)
          const Text('暂无卡片', style: TextStyle(color: Hud.dim))
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
                    color: Hud.tierColor(urgent.urgency()))),
          ]),
          Text(urgent.keepAliveAction,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Hud.muted)),
          const SizedBox(height: 10),
          Row(children: [
            Text(
                'P1 ${tier(UrgencyTier.p1)} · P2 ${tier(UrgencyTier.p2)} · OK ${tier(UrgencyTier.ok)}',
                style: Hud.mono.copyWith(fontSize: 11, color: Hud.muted)),
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
        const HudLabel('03 / Cost Engine (CNY)', color: Hud.emerald),
        const SizedBox(height: 10),
        Text('¥${monthly.toStringAsFixed(2)}',
            style:
                Hud.mono.copyWith(fontSize: 30, fontWeight: FontWeight.w900)),
        Text('/ 月 · 年化 ¥${(monthly * 12).toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 11, color: Hud.muted)),
        const SizedBox(height: 12),
        Text(
            exchangeRatesToCny.entries
                .where((e) =>
                    e.key != 'CNY' && _cards.any((c) => c.currency == e.key))
                .map((e) => '${e.key} ${e.value}')
                .join('  '),
            style: Hud.mono.copyWith(fontSize: 10.5, color: Hud.dim)),
      ]),
      _BentoTile(
        key: const Key('estk-bento'),
        children: [
          EstkMatrixCard(
            layout: layout,
            selectedSlot: _slot,
            onSelectSlot: (n) => setState(() => _slot = n),
            onWriteToSlot: (n) => _openForm(presetSlot: n),
          ),
        ],
      ),
    ];

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
          color: Hud.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Hud.line),
        ),
        child: Row(children: [
          const Icon(Icons.search, size: 18, color: Hud.dim),
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
              style: Hud.mono.copyWith(fontSize: 11, color: Hud.muted)),
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

  Widget _gallery(List<SimCard> cards) {
    if (cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          const Icon(Icons.sim_card_outlined, size: 48, color: Hud.dim),
          const SizedBox(height: 8),
          Text(_cards.isEmpty ? '金库为空，点击「新增 SIM」或从 JSON 备份导入' : '当前筛选无卡片',
              style: const TextStyle(color: Hud.muted)),
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

class _BentoTile extends StatelessWidget {
  const _BentoTile({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1730), Color(0xFF070D1C)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Hud.line),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}
